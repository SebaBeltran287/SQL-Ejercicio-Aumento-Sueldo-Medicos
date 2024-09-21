-- Crear la tabla MEDICO_AUMENTO para registrar la información del proceso
CREATE TABLE MEDICO_AUMENTO (
    rut                VARCHAR2(15),
    nombre             VARCHAR2(100),
    cargo              VARCHAR2(50),
    sueldo             NUMBER(10,2),
    antiguedad         NUMBER(5),
    porc_antiguedad    NUMBER(5,2),
    valor_antiguedad   NUMBER(10,2),
    porc_cantidad      NUMBER(5,2),
    valor_cantidad     NUMBER(10,2),
    porc_atenciones    NUMBER(5,2),
    valor_atenciones   NUMBER(10,2),
    especialidades     VARCHAR2(50)
);

-- Crear la tabla AUDITORIA para respaldar el proceso
CREATE TABLE AUDITORIA (
    rut                VARCHAR2(15),
    atenciones         NUMBER,
    promAten           NUMBER,
    atencionFonasa     NUMBER,
    especialidades     NUMBER
);

-- Crear tabla TRAMO_ASIG_ATMED para almacenar los porcentajes de aumento por antigüedad
CREATE TABLE TRAMO_ASIG_ATMED (
    antiguedad_min     NUMBER,
    antiguedad_max     NUMBER,
    porc_antiguedad    NUMBER(5,2)
);

-- Bloque anónimo para realizar el proceso de actualización de sueldos y registro de auditoría
DECLARE
    -- Definir una variable bind para el año a procesar
    v_anio_proceso NUMBER := EXTRACT(YEAR FROM SYSDATE) - 1;

    -- Definir un cursor explícito para procesar a los médicos con atenciones en el año anterior
    CURSOR cur_medicos IS
        SELECT M.rut, M.nombre, M.cargo, M.sueldo, M.fecha_ingreso, 
               COUNT(A.id_atencion) AS total_atenciones,
               SUM(CASE WHEN A.tipo_paciente = 'FONASA' THEN 1 ELSE 0 END) AS atenciones_fonasa,
               (SELECT COUNT(*) FROM MEDICO_ESPECIALIDAD WHERE MEDICO_ESPECIALIDAD.rut_medico = M.rut) AS especialidades
        FROM MEDICOS M
        JOIN ATENCIONES A ON M.rut = A.rut_medico
        WHERE EXTRACT(YEAR FROM A.fecha_atencion) = v_anio_proceso
        GROUP BY M.rut, M.nombre, M.cargo, M.sueldo, M.fecha_ingreso;

    -- Estructura de RECORD para almacenar los datos de la tabla MEDICO_AUMENTO
    rec_aumento MEDICO_AUMENTO%ROWTYPE;

    -- Variables adicionales
    v_promedio_atenciones NUMBER;
    v_porcentajes VARRAY(2) OF NUMBER := VARRAY(2)(2, 3); -- 2% para atenciones sobre el promedio y 3% para atenciones FONASA
    v_valor_antiguedad NUMBER;
    v_valor_cantidad NUMBER;
    v_valor_atenciones NUMBER;
    v_antiguedad NUMBER;

BEGIN
    -- Limpiar la tabla MEDICO_AUMENTO antes de iniciar el proceso
    DELETE FROM MEDICO_AUMENTO;

    -- Obtener el promedio de atenciones de todos los médicos en el año anterior
    SELECT AVG(total_atenciones)
    INTO v_promedio_atenciones
    FROM (
        SELECT COUNT(A.id_atencion) AS total_atenciones
        FROM ATENCIONES A
        WHERE EXTRACT(YEAR FROM A.fecha_atencion) = v_anio_proceso
        GROUP BY A.rut_medico
    );

    -- Abrir el cursor y procesar cada médico
    FOR rec_medico IN cur_medicos LOOP
        -- Calcular la antigüedad del médico
        v_antiguedad := EXTRACT(YEAR FROM SYSDATE) - EXTRACT(YEAR FROM rec_medico.fecha_ingreso);

        -- Obtener el porcentaje de antigüedad según la tabla TRAMO_ASIG_ATMED
        SELECT porc_antiguedad INTO rec_aumento.porc_antiguedad
        FROM TRAMO_ASIG_ATMED
        WHERE v_antiguedad BETWEEN antiguedad_min AND antiguedad_max;

        -- Calcular el valor adicional por antigüedad
        v_valor_antiguedad := rec_medico.sueldo * rec_aumento.porc_antiguedad / 100;

        -- Calcular el valor adicional por cantidad de atenciones si está sobre el promedio
        IF rec_medico.total_atenciones > v_promedio_atenciones THEN
            rec_aumento.porc_cantidad := v_porcentajes(1); -- 2%
            v_valor_cantidad := rec_medico.sueldo * rec_aumento.porc_cantidad / 100;
        ELSE
            rec_aumento.porc_cantidad := 0;
            v_valor_cantidad := 0;
        END IF;

        -- Calcular el valor adicional por atenciones FONASA
        rec_aumento.porc_atenciones := v_porcentajes(2); -- 3%
        v_valor_atenciones := rec_medico.sueldo * rec_aumento.porc_atenciones / 100;

        -- Verificar si el médico tiene más de una especialidad
        IF rec_medico.especialidades > 1 THEN
            rec_aumento.especialidades := 'más de una especialidad';
        ELSE
            rec_aumento.especialidades := 'una especialidad';
        END IF;

        -- Insertar los datos en la tabla MEDICO_AUMENTO
        INSERT INTO MEDICO_AUMENTO VALUES (
            rec_medico.rut,
            rec_medico.nombre,
            rec_medico.cargo,
            rec_medico.sueldo,
            v_antiguedad,
            rec_aumento.porc_antiguedad,
            v_valor_antiguedad,
            rec_aumento.porc_cantidad,
            v_valor_cantidad,
            rec_aumento.porc_atenciones,
            v_valor_atenciones,
            rec_aumento.especialidades
        );

        -- Insertar los datos de auditoría en la tabla AUDITORIA
        INSERT INTO AUDITORIA VALUES (
            rec_medico.rut,
            rec_medico.total_atenciones,
            v_promedio_atenciones,
            rec_medico.atenciones_fonasa,
            rec_medico.especialidades
        );
    END LOOP;
    
    -- Commit para guardar los cambios
    COMMIT;
    
END;
/
