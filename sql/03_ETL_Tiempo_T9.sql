/* =====================================================================
   T9 - Calendario: carga de DIM_Tiempo
   Genera un dia por fila, continuo, con anios completos (2024 y 2025),
   CONTINUO -> no hay dias saltados
   AÑOS COMPLETOS -> desde enero del 2024 hasta diciembre de 2025
   ESPAÑOL -> los nombres se escriben a mano con CHOOSE
   con nombres en espanol que NO dependen del idioma ni del DATEFIRST del servidor.
   Requiere: 01_Crear_DW.sql ya ejecutado (la tabla y la fila -1 ya existen).
   Re-ejecutable: solo inserta los dias que faltan; no borra nada ni toca la fila -1.
   ===================================================================== */
USE FINALBI_DW_GrupoN;
GO
SET NOCOUNT ON; -- apaga los mensajes o avisos para un log mas limpio

DECLARE @Inicio DATE = '2024-01-01';   --  VARIABLES: primer dia del primer anio (debe ser 1 de enero)
DECLARE @Fin    DATE = '2025-12-31';   -- ultimo dia del ultimo anio (debe ser 31 de diciembre)

;WITH Fechas AS ( --usamos un cte(consulta con nombre que se usa a continuacion que es recursiva)
    SELECT @Inicio AS Fecha -- produce una fila 2024-01-01
    UNION ALL -- recusrivo: toma el ultimo dia generado y le suma 1
    SELECT DATEADD(DAY, 1, Fecha) FROM Fechas WHERE Fecha < @Fin -- se detiene al llegar a 31-12-25
),
Base AS ( -- otra cte para descomponer la fecha
    SELECT
        Fecha,
        YEAR(Fecha)  AS Anio,  -- se extraen las partes de la fecha 
        MONTH(Fecha) AS Mes,
        DAY(Fecha)   AS Dia,
        -- 1=Lunes ... 7=Domingo. El 1-ene-1900 fue lunes; no usa DATEPART(WEEKDAY) para no depender de DATEFIRST.
        (DATEDIFF(DAY, '19000101', Fecha) % 7) + 1 AS DiaSemana -- cuenta cuantos dias pasaron desde el 1-enero-1900 divde en 7 y +1 hace que el resultado vaya de 1 a 7 para que nos de el dia en que fue 1-ene-1900 (lunes)
    FROM Fechas
)
INSERT INTO dbo.DIM_Tiempo --ACA ESCRIBIMOS DIRECTO EN LAS TABLAS DE DW
    (TiempoKey, Fecha, Anio, Trimestre, NombreTrimestre, Mes, NombreMes, AnioMes, Dia, DiaSemana, NombreDia, SemanaAnio, EsFinDeSemana)
SELECT
    Anio * 10000 + Mes * 100 + Dia                              AS TiempoKey,      -- yyyymmdd 
    Fecha, -- se copia
    Anio, -- se copia
    (Mes - 1) / 3 + 1                                            AS Trimestre,
    CONCAT(N'Trimestre ', DATEPART(QUARTER, Fecha))              AS NombreTrimestre,
    Mes,
    CHOOSE(Mes, N'Enero', N'Febrero', N'Marzo', N'Abril', N'Mayo', N'Junio',
                N'Julio', N'Agosto', N'Septiembre', N'Octubre', N'Noviembre', N'Diciembre') AS NombreMes, -- CHOOSE(Mes, 'Enero', 'Febrero', ...). Elige el elemento número Mes de la lista
    Anio * 100 + Mes                                             AS AnioMes,        -- yyyymm (202501), para ordenar
    Dia,
    DiaSemana,
    CHOOSE(DiaSemana, N'Lunes', N'Martes', N'Miércoles', N'Jueves', N'Viernes', N'Sábado', N'Domingo') AS NombreDia,
    DATEPART(ISO_WEEK, Fecha)                                    AS SemanaAnio,     -- semana ISO (1 a 53)
    CASE WHEN DiaSemana IN (6, 7) THEN 1 ELSE 0 END              AS EsFinDeSemana
FROM Base
WHERE NOT EXISTS (SELECT 1 FROM dbo.DIM_Tiempo t WHERE t.Fecha = Base.Fecha) -- solo inserta los dias que aun no estan en la tabla
OPTION (MAXRECURSION 0); -- para que la recursividad tenga un limite
GO

/* ---------------------------------------------------------------------
   Verificacion (deben cumplirse las 4 comprobaciones)
   --------------------------------------------------------------------- */
SELECT
    COUNT(*)                                   AS DiasCargados,           -- 731 (366 de 2024 + 365 de 2025)
    MIN(Fecha)                                 AS PrimerDia,              -- 2024-01-01
    MAX(Fecha)                                 AS UltimoDia,              -- 2025-12-31
    DATEDIFF(DAY, MIN(Fecha), MAX(Fecha)) + 1  AS DiasEsperados           -- debe ser igual a DiasCargados (sin huecos)
FROM dbo.DIM_Tiempo
WHERE TiempoKey <> -1;

SELECT Anio, COUNT(*) AS Dias, COUNT(DISTINCT Mes) AS Meses              -- 2024: 366 dias; 2025: 365 dias; 12 meses cada uno
FROM dbo.DIM_Tiempo WHERE TiempoKey <> -1 GROUP BY Anio ORDER BY Anio;

SELECT Fecha, NombreDia, NombreMes, NombreTrimestre, TiempoKey           -- 2024-01-01 debe ser Lunes / Enero / Trimestre 1 / 20240101
FROM dbo.DIM_Tiempo WHERE Fecha IN ('2024-01-01', '2024-02-29', '2025-11-28', '2025-12-31');

SELECT COUNT(*) AS FilaDesconocida FROM dbo.DIM_Tiempo WHERE TiempoKey = -1;  -- 1
GO

-- se usa CHOOSE  Y NO DATENAME para que los nombres salgna en español sin depender del idioma del server
-- El dia  de la semana es con DATEDIFF y no con DATEPART porque asi no dependemos de DATEFIRST