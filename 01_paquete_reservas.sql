-- Codigos de error: -20001 fechas | -20002 huespedes/capacidad | -20003 habitacion ocupada
--   -20004 (trigger de solape) | -20005 habitacion inexistente/inactiva | -20006 sin tarifa
--   -20007 cliente inexistente | -20008 check-in en el pasado | -20010 mes invalido
CREATE OR REPLACE PACKAGE pkg_turismo AS
  FUNCTION fn_valor_estadia(p_id_habitacion IN NUMBER, p_fecha_in IN DATE, p_fecha_out IN DATE)
    RETURN NUMBER;

  PROCEDURE sp_crear_reserva(
    p_id_cliente    IN  NUMBER,
    p_id_habitacion IN  NUMBER,
    p_fecha_in      IN  DATE,
    p_fecha_out     IN  DATE,
    p_huespedes     IN  NUMBER,
    p_id_reserva    OUT NUMBER);

  PROCEDURE sp_liquidacion_mensual(p_anio IN NUMBER, p_mes IN NUMBER);
END pkg_turismo;
/

CREATE OR REPLACE PACKAGE BODY pkg_turismo AS

  FUNCTION fn_valor_estadia(p_id_habitacion IN NUMBER, p_fecha_in IN DATE, p_fecha_out IN DATE)
    RETURN NUMBER IS
    v_in     DATE := TRUNC(p_fecha_in);
    v_out    DATE := TRUNC(p_fecha_out);
    v_total  NUMBER;
    v_noches NUMBER;
  BEGIN
    IF v_in IS NULL OR v_out IS NULL OR v_out <= v_in THEN
      RAISE_APPLICATION_ERROR(-20001,'La fecha de checkout debe ser posterior al checkin.');
    END IF;

    SELECT SUM(n.noches*n.valor_noche), SUM(n.noches)
      INTO v_total, v_noches
      FROM (SELECT tf.valor_noche,
                   LEAST(v_out,t.fecha_fin+1)-GREATEST(v_in,t.fecha_inicio) noches
              FROM temporada t
              JOIN tarifa tf ON tf.id_temporada=t.id_temporada
             WHERE tf.id_habitacion=p_id_habitacion
               AND t.fecha_inicio<v_out AND t.fecha_fin>=v_in) n;

    IF v_noches IS NULL OR v_noches <> (v_out-v_in) THEN
      RAISE_APPLICATION_ERROR(-20006,'La habitacion no tiene tarifa para todas las noches solicitadas.');
    END IF;
    RETURN v_total;
  END fn_valor_estadia;

  PROCEDURE sp_crear_reserva(
    p_id_cliente    IN  NUMBER,
    p_id_habitacion IN  NUMBER,
    p_fecha_in      IN  DATE,
    p_fecha_out     IN  DATE,
    p_huespedes     IN  NUMBER,
    p_id_reserva    OUT NUMBER) IS
    v_in        DATE := TRUNC(p_fecha_in);
    v_out       DATE := TRUNC(p_fecha_out);
    v_capacidad habitacion.capacidad%TYPE;
    v_activa    habitacion.activa%TYPE;
    v_existe    NUMBER;
    v_solapes   NUMBER;
    v_valor     NUMBER;
  BEGIN
    IF v_in IS NULL OR v_out IS NULL OR v_out <= v_in THEN
      RAISE_APPLICATION_ERROR(-20001,'La fecha de checkout debe ser posterior al checkin.');
    END IF;
    IF v_in < TRUNC(SYSDATE) THEN
      RAISE_APPLICATION_ERROR(-20008,'No se puede reservar con check-in en el pasado.');
    END IF;

    BEGIN
      SELECT capacidad, activa INTO v_capacidad, v_activa
        FROM habitacion WHERE id_habitacion=p_id_habitacion FOR UPDATE;
    EXCEPTION WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20005,'La habitacion '||p_id_habitacion||' no existe.');
    END;
    IF v_activa <> 'S' THEN
      RAISE_APPLICATION_ERROR(-20005,'La habitacion '||p_id_habitacion||' esta inactiva.');
    END IF;

    SELECT COUNT(*) INTO v_existe FROM cliente WHERE id_cliente=p_id_cliente;
    IF v_existe = 0 THEN
      RAISE_APPLICATION_ERROR(-20007,'El cliente '||p_id_cliente||' no existe.');
    END IF;

    IF p_huespedes IS NULL OR p_huespedes < 1 OR p_huespedes > v_capacidad THEN
      RAISE_APPLICATION_ERROR(-20002,'Huespedes invalidos: debe estar entre 1 y la capacidad maxima ('||v_capacidad||').');
    END IF;

    SELECT COUNT(*) INTO v_solapes
      FROM reserva_habitacion rh JOIN reserva r ON r.id_reserva=rh.id_reserva
     WHERE rh.id_habitacion=p_id_habitacion
       AND r.estado IN ('CONFIRMADA','COMPLETADA')
       AND rh.fecha_checkin<v_out AND rh.fecha_checkout>v_in;
    IF v_solapes > 0 THEN
      RAISE_APPLICATION_ERROR(-20003,'La habitacion no esta disponible para las fechas seleccionadas.');
    END IF;

    v_valor := fn_valor_estadia(p_id_habitacion, v_in, v_out);  -- valida que exista tarifa

    INSERT INTO reserva(id_cliente,fecha_reserva,fecha_checkin,fecha_checkout,estado,numero_huespedes)
    VALUES(p_id_cliente,TRUNC(SYSDATE),v_in,v_out,'PENDIENTE',p_huespedes)
    RETURNING id_reserva INTO p_id_reserva;

    INSERT INTO reserva_habitacion(id_reserva,id_habitacion,fecha_checkin,fecha_checkout,huespedes)
    VALUES(p_id_reserva,p_id_habitacion,v_in,v_out,p_huespedes);

    COMMIT;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    p_id_reserva := NULL;
    RAISE;
  END sp_crear_reserva;

  PROCEDURE sp_liquidacion_mensual(p_anio IN NUMBER, p_mes IN NUMBER) IS
    CURSOR c_liquidacion(pc_ini DATE, pc_fin DATE) IS
      SELECT m.nombre AS municipio, a.nombre AS alojamiento,
             COUNT(p.id_pago) AS pagos, SUM(p.monto) AS total_recaudado
        FROM pago p
        JOIN (SELECT DISTINCT rh.id_reserva, h.id_alojamiento
                FROM reserva_habitacion rh
                JOIN habitacion h ON h.id_habitacion=rh.id_habitacion) ra
          ON ra.id_reserva=p.id_reserva
        JOIN alojamiento a ON a.id_alojamiento=ra.id_alojamiento
        JOIN municipio m ON m.id_municipio=a.id_municipio
       WHERE p.estado='EXITOSO' AND p.fecha_pago>=pc_ini AND p.fecha_pago<pc_fin
       GROUP BY m.nombre, a.nombre
       ORDER BY m.nombre, SUM(p.monto) DESC;

    v_ini        DATE;
    v_total_mes  NUMBER := 0;
    v_filas      PLS_INTEGER := 0;
  BEGIN
    IF p_anio IS NULL OR p_mes IS NULL OR p_mes NOT BETWEEN 1 AND 12 THEN
      RAISE_APPLICATION_ERROR(-20010,'Mes invalido: debe estar entre 1 y 12.');
    END IF;
    v_ini := TO_DATE(TO_CHAR(p_anio,'FM0000')||TO_CHAR(p_mes,'FM00'),'YYYYMM');

    DBMS_OUTPUT.PUT_LINE('--- LIQUIDACION MENSUAL '||TO_CHAR(p_mes,'FM00')||'/'||p_anio||' ---');
    FOR reg IN c_liquidacion(v_ini, ADD_MONTHS(v_ini,1)) LOOP
      DBMS_OUTPUT.PUT_LINE(RPAD(reg.municipio,12)||' | '||RPAD(reg.alojamiento,26)
        ||' | pagos: '||LPAD(reg.pagos,3)||' | recaudo: $'||TO_CHAR(reg.total_recaudado,'FM999G999G999G990'));
      v_total_mes := v_total_mes + reg.total_recaudado;
      v_filas := v_filas + 1;
    END LOOP;
    IF v_filas = 0 THEN
      DBMS_OUTPUT.PUT_LINE('Sin pagos exitosos en el periodo.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('TOTAL DEL MES: $'||TO_CHAR(v_total_mes,'FM999G999G999G990'));
  END sp_liquidacion_mensual;

END pkg_turismo;
/
SHOW ERRORS