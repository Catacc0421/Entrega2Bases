SET SERVEROUTPUT ON SIZE UNLIMITED

-- 1. fn_valor_estadia cruzando temporadas
DECLARE
  v_valor NUMBER;
BEGIN
  v_valor := pkg_turismo.fn_valor_estadia(1, DATE '2024-03-20', DATE '2024-03-27');
  DBMS_OUTPUT.PUT_LINE('Valor de la estadia: $'||TO_CHAR(v_valor,'FM999G999G999G990'));
END;
/
-- Verificacion manual: la suma de subtotales debe coincidir con la funcion
SELECT t.nombre temporada,
       LEAST(DATE '2024-03-27',t.fecha_fin+1)-GREATEST(DATE '2024-03-20',t.fecha_inicio) noches,
       tf.valor_noche,
       (LEAST(DATE '2024-03-27',t.fecha_fin+1)-GREATEST(DATE '2024-03-20',t.fecha_inicio))*tf.valor_noche subtotal
FROM temporada t JOIN tarifa tf ON tf.id_temporada=t.id_temporada
WHERE tf.id_habitacion=1 AND t.fecha_inicio<DATE '2024-03-27' AND t.fecha_fin>=DATE '2024-03-20'
ORDER BY t.fecha_inicio;

-- 2. Auditoria de tarifas: un UPDATE de 3 filas deja 3 registros; luego se revierte
UPDATE tarifa SET valor_noche = ROUND(valor_noche*1.05,-3)
WHERE id_habitacion IN (1,2,3) AND id_temporada=1;
SELECT id_auditoria, usuario, id_habitacion, id_temporada, valor_anterior, valor_nuevo
FROM auditoria_tarifa ORDER BY id_auditoria;
ROLLBACK;

-- 3. sp_crear_reserva: una prueba por cada excepcion + un caso valido
DECLARE
  v_hab NUMBER; v_in DATE; v_out DATE;

  PROCEDURE intento(p_caso VARCHAR2, p_cli NUMBER, p_hab NUMBER, p_in DATE, p_out DATE, p_hues NUMBER) IS
    v_id NUMBER;
  BEGIN
    pkg_turismo.sp_crear_reserva(p_cli,p_hab,p_in,p_out,p_hues,v_id);
    DBMS_OUTPUT.PUT_LINE(RPAD(p_caso,26)||'-> OK, reserva '||v_id||' (se borra)');
    DELETE FROM reserva WHERE id_reserva=v_id;
    COMMIT;
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE(RPAD(p_caso,26)||'-> '||SQLERRM);
  END;
BEGIN
  SELECT rh.id_habitacion, rh.fecha_checkin, rh.fecha_checkout INTO v_hab, v_in, v_out
    FROM reserva_habitacion rh JOIN reserva r ON r.id_reserva=rh.id_reserva
   WHERE r.estado='CONFIRMADA' AND rh.fecha_checkin>TRUNC(SYSDATE)+1
   FETCH FIRST 1 ROW ONLY;

  intento('-20001 fechas invalidas', 1,1,        DATE '2026-12-24',DATE '2026-12-20',2);
  intento('-20008 check-in pasado',  1,1,        DATE '2020-01-10',DATE '2020-01-12',2);
  intento('-20005 habitacion',       1,999999,   DATE '2026-12-20',DATE '2026-12-24',2);
  intento('-20007 cliente',          999999,1,   DATE '2026-12-20',DATE '2026-12-24',2);
  intento('-20002 capacidad',        1,1,        DATE '2026-12-20',DATE '2026-12-24',99);
  intento('-20003 ocupada',          1,v_hab,    v_in,v_out,1);
  intento('-20006 sin tarifa (2030)',1,1,        DATE '2030-01-10',DATE '2030-01-13',2);
  intento('Caso valido',             1,1,        DATE '2026-12-20',DATE '2026-12-24',2);
END;
/

-- 4. Disparadores de solape
DECLARE
  v1 NUMBER; v2 NUMBER; v3 NUMBER;
BEGIN
  pkg_turismo.sp_crear_reserva(2,1,DATE '2026-12-26',DATE '2026-12-29',2,v1);
  pkg_turismo.sp_crear_reserva(3,1,DATE '2026-12-27',DATE '2026-12-30',2,v2);
  DBMS_OUTPUT.PUT_LINE('Dos PENDIENTES solapadas creadas: '||v1||' y '||v2);

  UPDATE reserva SET estado='CONFIRMADA' WHERE id_reserva=v1;
  DBMS_OUTPUT.PUT_LINE('Confirmar la primera: OK');

  BEGIN
    UPDATE reserva SET estado='CONFIRMADA' WHERE id_reserva=v2;
    DBMS_OUTPUT.PUT_LINE('ERROR: la segunda confirmacion no fue rechazada');
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Confirmar la segunda -> '||SQLERRM);
  END;

  INSERT INTO reserva(id_cliente,fecha_reserva,fecha_checkin,fecha_checkout,estado,numero_huespedes)
  VALUES(4,TRUNC(SYSDATE),DATE '2026-12-27',DATE '2026-12-30','CONFIRMADA',2)
  RETURNING id_reserva INTO v3;
  BEGIN
    INSERT INTO reserva_habitacion(id_reserva,id_habitacion,fecha_checkin,fecha_checkout,huespedes)
    VALUES(v3,1,DATE '2026-12-27',DATE '2026-12-30',2);
    DBMS_OUTPUT.PUT_LINE('ERROR: el INSERT solapado no fue rechazado');
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('INSERT solapado -> '||SQLERRM);
  END;

  DELETE FROM reserva WHERE id_reserva IN (v1,v2,v3);
  COMMIT;
END;
/

-- 5. Liquidacion mensual (cursor explicito) y control contra una suma directa
BEGIN
  pkg_turismo.sp_liquidacion_mensual(2025,4);
END;
/
SELECT SUM(monto) total_control FROM pago
WHERE estado='EXITOSO' AND fecha_pago>=DATE '2025-04-01' AND fecha_pago<DATE '2025-05-01';

BEGIN
  pkg_turismo.sp_liquidacion_mensual(2025,13);
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('Mes 13 -> '||SQLERRM);
END;
/

-- 6. Vista materializada: refresco completo manual
BEGIN DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL','C'); END;
/
SELECT COUNT(*) filas_mv FROM mv_ocupacion_mensual;