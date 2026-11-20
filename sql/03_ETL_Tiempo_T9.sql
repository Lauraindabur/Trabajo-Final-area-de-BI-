/* =====================================================================
   T9 - Calendario: carga de DIM_Tiempo
   Genera un dia por fila, continuo, con anios completos (2024 y 2025),
   con nombres en espanol que NO dependen del idioma ni del DATEFIRST del servidor.
   Requiere: 01_Crear_DW.sql ya ejecutado (la tabla y la fila -1 ya existen).
   Re-ejecutable: solo inserta los dias que faltan; no borra nada ni toca la fila -1.
   ===================================================================== */
USE FINALBI_DW_GrupoN;
GO
SET NOCOUNT ON;

DECLARE @Inicio DATE = '2024-01-01';   -- primer dia del primer anio (debe ser 1 de enero)
DECLARE @Fin    DATE = '2025-12-31';   -- ultimo dia del ultimo anio (debe ser 31 de diciembre)

;WITH Fechas AS (
    SELECT @Inicio AS Fecha
    UNION ALL
    SELECT DATEADD(DAY, 1, Fecha) FROM Fechas WHERE Fecha < @Fin
),
Base AS (
    SELECT
        Fecha,
        YEAR(Fecha)  AS Anio,
        MONTH(Fecha) AS Mes,
        DAY(Fecha)   AS Dia,
        -- 1=Lunes ... 7=Domingo. El 1-ene-1900 fue lunes; no usa DATEPART(WEEKDAY) para no depender de DATEFIRST.
        (DATEDIFF(DAY, '19000101', Fecha) % 7) + 1 AS DiaSemana
    FROM Fechas
)
INSERT INTO dbo.DIM_Tiempo
    (TiempoKey, Fecha, Anio, Trimestre, NombreTrimestre, Mes, NombreMes, AnioMes, Dia, DiaSemana, NombreDia, SemanaAnio, EsFinDeSemana)
SELECT
    Anio * 10000 + Mes * 100 + Dia                              AS TiempoKey,      -- yyyymmdd
    Fecha,
    Anio,
    (Mes - 1) / 3 + 1                                            AS Trimestre,
    CONCAT(N'Trimestre ', DATEPART(QUARTER, Fecha))              AS NombreTrimestre,
    Mes,
    CHOOSE(Mes, N'Enero', N'Febrero', N'Marzo', N'Abril', N'Mayo', N'Junio',
                N'Julio', N'Agosto', N'Septiembre', N'Octubre', N'Noviembre', N'Diciembre') AS NombreMes,
    Anio * 100 + Mes                                             AS AnioMes,        -- yyyymm, para ordenar
    Dia,
    DiaSemana,
    CHOOSE(DiaSemana, N'Lunes', N'Martes', N'Miércoles', N'Jueves', N'Viernes', N'Sábado', N'Domingo') AS NombreDia,
    DATEPART(ISO_WEEK, Fecha)                                    AS SemanaAnio,     -- semana ISO (1 a 53)
    CASE WHEN DiaSemana IN (6, 7) THEN 1 ELSE 0 END              AS EsFinDeSemana
FROM Base
WHERE NOT EXISTS (SELECT 1 FROM dbo.DIM_Tiempo t WHERE t.Fecha = Base.Fecha)
OPTION (MAXRECURSION 0);
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
