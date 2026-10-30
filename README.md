Proyecto Integrador - TurismoUQ 🌄

Plataforma de reservas turísticas del Quindío

Este repositorio contiene los scripts correspondientes a la Entrega 2 (Capa PL/SQL) del proyecto integrador para la gestión de alojamientos, tarifas y reservas en el departamento del Quindío.

🏛 Información Académica

Universidad: Universidad del Quindío

Programa: Ingeniería de Sistemas y Computación

Asignatura: Bases de Datos II

Docente: Carolina Londoño Idárraga

Grupo: 01N

Periodo: 2026-2

👥 Integrantes del Equipo

Juan David López Muñoz Cod: 1010065872

Catalina Clavijo Cifuentes Cod: 1092851309

Entrega: Catalina Clavijo Cifuentes

📂 Estructura del Repositorio y Orden de Ejecución

Para evaluar la entrega, los scripts deben ejecutarse en el motor Oracle XE 21c (bajo el usuario TURISMOUQ) respetando la estructura de la base de datos de la Entrega 1 y en el siguiente orden estricto:

01_paquete_reservas.sql: Contiene la especificación y el cuerpo del paquete pkg_turismo, el cual incluye:

Función fn_valor_estadia para el cálculo de tarifas por noches cruzando temporadas.

Procedimiento sp_crear_reserva con validaciones de capacidad, fechas y disponibilidad.

Procedimiento sp_liquidacion_mensual apoyado en un cursor explícito.

02_disparadores.sql: Incluye la tabla de auditoría y los triggers (nivel de fila) para registrar los cambios en los precios de las tarifas y para evitar el solapamiento de reservas confirmadas.

03_arquitectura.sql: Contiene la creación del Tablespace destinado al histórico de reservas y la Vista Materializada para la ocupación mensual (ambos con la justificación técnica comentada en el código).

04_pruebas.sql: Script destinado a ejecutar las funciones, procedimientos y forzar las excepciones programadas.



Contar con el esquema TURISMOUQ previamente creado.

Haber ejecutado los scripts DDL y de carga masiva correspondientes a la Entrega 1 antes de compilar estos componentes PL/SQL.
