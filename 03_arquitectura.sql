-- 1. Tablespace propio para el historico de reservas.
-- Justificacion: separa las tablas transaccionales pesadas (reservas, pagos, servicios) del
-- catalogo, aisla su I/O y permite respaldos y compresion independientes.
-- Si da error por el nombre del archivo, usa esta variante con ruta:
--   CREATE TABLESPACE ts_historico_reservas
--     DATAFILE '/opt/oracle/oradata/FREE/FREEPDB1/historico_reservas_01.dbf' SIZE 50M
--     AUTOEXTEND ON NEXT 10M MAXSIZE 500M LOGGING;
CREATE TABLESPACE ts_historico_reservas
  DATAFILE SIZE 50M AUTOEXTEND ON NEXT 10M MAXSIZE 500M
  LOGGING;

-- Mover las tablas del historico al tablespace (MOVE ONLINE no bloquea lecturas/escrituras).
ALTER TABLE reserva            MOVE ONLINE TABLESPACE ts_historico_reservas;
ALTER TABLE reserva_habitacion MOVE ONLINE TABLESPACE ts_historico_reservas;
ALTER TABLE reserva_servicio   MOVE ONLINE TABLESPACE ts_historico_reservas;
ALTER TABLE pago               MOVE ONLINE TABLESPACE ts_historico_reservas;

BEGIN
  FOR i IN (SELECT index_name FROM user_indexes
             WHERE table_name IN ('RESERVA','RESERVA_HABITACION','RESERVA_SERVICIO','PAGO')
               AND index_type='NORMAL' AND tablespace_name<>'TS_HISTORICO_RESERVAS') LOOP
    EXECUTE IMMEDIATE 'ALTER INDEX '||i.index_name||' REBUILD ONLINE TABLESPACE ts_historico_reservas';
  END LOOP;
END;
/

SELECT table_name, tablespace_name FROM user_tables ORDER BY tablespace_name, table_name;

-- 2. Vista materializada de ocupacion mensual (noches prorrateadas por mes).
-- Politica de refresco: COMPLETE ON DEMAND. Es un reporte gerencial que no necesita tiempo real;
-- se refresca con un job nocturno en horas de baja carga.
CREATE MATERIALIZED VIEW mv_ocupacion_mensual
  BUILD IMMEDIATE
  REFRESH COMPLETE ON DEMAND
AS
SELECT a.id_alojamiento,
       m.nombre AS municipio,
       a.nombre AS alojamiento,
       EXTRACT(YEAR FROM x.mes)  AS anio,
       EXTRACT(MONTH FROM x.mes) AS mes,
       NVL(SUM(GREATEST(0, LEAST(l.fecha_checkout,ADD_MONTHS(x.mes,1)) - GREATEST(l.fecha_checkin,x.mes))),0)
         AS noches_ocupadas,
       hc.habitaciones * (ADD_MONTHS(x.mes,1)-x.mes) AS noches_disponibles
FROM alojamiento a
JOIN municipio m ON m.id_municipio=a.id_municipio
JOIN (SELECT id_alojamiento, COUNT(*) habitaciones FROM habitacion GROUP BY id_alojamiento) hc
  ON hc.id_alojamiento=a.id_alojamiento
CROSS JOIN (SELECT ADD_MONTHS(DATE '2024-01-01',LEVEL-1) mes FROM dual CONNECT BY LEVEL<=36) x
LEFT JOIN (SELECT h.id_alojamiento, rh.fecha_checkin, rh.fecha_checkout
             FROM reserva_habitacion rh
             JOIN reserva r ON r.id_reserva=rh.id_reserva
             JOIN habitacion h ON h.id_habitacion=rh.id_habitacion
            WHERE r.estado IN ('CONFIRMADA','COMPLETADA')) l
  ON l.id_alojamiento=a.id_alojamiento
 AND l.fecha_checkin<ADD_MONTHS(x.mes,1) AND l.fecha_checkout>x.mes
GROUP BY a.id_alojamiento, m.nombre, a.nombre, x.mes, hc.habitaciones;

-- Job de refresco diario a medianoche
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'JOB_REFRESCO_MV_OCUPACION',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN DBMS_MVIEW.REFRESH(''MV_OCUPACION_MENSUAL'',''C''); END;',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=DAILY;BYHOUR=0;BYMINUTE=0;BYSECOND=0',
    enabled         => TRUE);
END;
/

-- Ejemplo: los 10 alojamientos mas ocupados en abril de 2025
SELECT municipio, alojamiento, anio, mes, noches_ocupadas, noches_disponibles,
       ROUND(100*noches_ocupadas/noches_disponibles,2) ocupacion_pct
FROM mv_ocupacion_mensual
WHERE anio=2025 AND mes=4
ORDER BY ocupacion_pct DESC
FETCH FIRST 10 ROWS ONLY;