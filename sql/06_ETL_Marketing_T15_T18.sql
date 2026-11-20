/* =====================================================================
   06 · ETL DE MARKETING DESDE MONGODB  [T15, T16, T17, T18]
   Carga DIM_CanalMarketing, DIM_Campana y FACT_InteraccionMarketing.
   Parte: stg.mongo_campanas y stg.mongo_interacciones (las llena Extraer_Mongo.py).
   Persona de marketing (origen: MarketingP3.sql), ajustado a este DW:
     - Fechas de texto (dd/mm/aaaa hh:mm) con estilo 103 EXPLICITO y las ISO con 126
       (con TRY_CAST el resultado dependia del idioma del servidor).
     - CuponRedimido se toma del campo cuponRedimido del documento (no es un tipo de evento).
     - La fecha parseada de cada evento se guarda en stg.Interaccion_Evento (la reutiliza T19).
   REQUISITOS: 03_ETL_Tiempo_T9, 04_ETL_Dimensiones_y_Ventas y 05_ETL_Cliente_Mongo ejecutados.
   Re-ejecutable.
   ===================================================================== */
USE FINALBI_DW_GrupoN;
GO

IF OBJECT_ID(N'stg.mongo_interacciones') IS NULL OR OBJECT_ID(N'stg.mongo_campanas') IS NULL
    THROW 50006, N'Faltan stg.mongo_campanas / stg.mongo_interacciones: ejecute Extraer_Mongo.py.', 1;
GO

/* 1. DIM_CanalMarketing (el DW ya trae los 4 canales; esto agrega cualquiera nuevo) */
MERGE dbo.DIM_CanalMarketing AS tgt
USING (
    SELECT DISTINCT LOWER(TRIM(Canal)) AS CanalMarketingID,
        CASE LOWER(TRIM(Canal))
            WHEN N'email' THEN N'Email' WHEN N'sms' THEN N'SMS' WHEN N'whatsapp' THEN N'WhatsApp'
            WHEN N'redes_sociales' THEN N'Redes sociales'
            ELSE UPPER(LEFT(TRIM(Canal), 1)) + LOWER(SUBSTRING(TRIM(Canal), 2, 28)) END AS NombreCanal
    FROM stg.mongo_interacciones
    WHERE Canal IS NOT NULL AND TRIM(Canal) <> N''
) AS src ON tgt.CanalMarketingID = src.CanalMarketingID
WHEN NOT MATCHED THEN INSERT (CanalMarketingID, NombreCanal) VALUES (src.CanalMarketingID, src.NombreCanal);
GO

/* 2. T18 · DIM_Campana
      presupuesto en texto ('9.800.000') -> DECIMAL(18,2); responsable faltante -> 'Sin asignar'
      descuento: viene del campo descuentoOfrecido (entero) */
MERGE dbo.DIM_Campana AS tgt
USING (
    SELECT TRIM(CampanaID) AS CampanaID,
        COALESCE(NULLIF(TRIM(NombreCampana), N''), N'Sin nombre')   AS NombreCampana,
        COALESCE(NULLIF(TRIM(Objetivo), N''), N'Desconocido')       AS Objetivo,
        COALESCE(TRY_CONVERT(DATE, FechaInicio, 23), TRY_CONVERT(DATE, FechaInicio, 103)) AS FechaInicio,
        COALESCE(TRY_CONVERT(DATE, FechaFin, 23),    TRY_CONVERT(DATE, FechaFin, 103))    AS FechaFin,
        COALESCE(NULLIF(TRIM(Canales), N''), N'Desconocido')        AS Canales,
        COALESCE(NULLIF(TRIM(CategoriasPromocionadas), N''), N'Todas') AS CategoriasPromocionadas,
        COALESCE(TRY_CAST(REPLACE(TRIM(PorcentajeDescuento), N',', N'.') AS DECIMAL(5,2)), 0) AS PorcentajeDescuento,
        COALESCE(NULLIF(TRIM(CodigoCupon), N''), N'Sin cupon')      AS CodigoCupon,
        COALESCE(TRY_CAST(REPLACE(REPLACE(TRIM(Presupuesto), N'$', N''), N'.', N'') AS DECIMAL(18,2)), 0) AS Presupuesto,
        COALESCE(NULLIF(TRIM(Responsable), N''), N'Sin asignar')    AS Responsable
    FROM stg.mongo_campanas
) AS src ON tgt.CampanaID = src.CampanaID
WHEN MATCHED THEN UPDATE SET
    tgt.NombreCampana = src.NombreCampana, tgt.Objetivo = src.Objetivo, tgt.FechaInicio = src.FechaInicio,
    tgt.FechaFin = src.FechaFin, tgt.Canales = src.Canales, tgt.CategoriasPromocionadas = src.CategoriasPromocionadas,
    tgt.PorcentajeDescuento = src.PorcentajeDescuento, tgt.CodigoCupon = src.CodigoCupon,
    tgt.Presupuesto = src.Presupuesto, tgt.Responsable = src.Responsable
WHEN NOT MATCHED THEN INSERT (CampanaID, NombreCampana, Objetivo, FechaInicio, FechaFin, Canales,
        CategoriasPromocionadas, PorcentajeDescuento, CodigoCupon, Presupuesto, Responsable)
    VALUES (src.CampanaID, src.NombreCampana, src.Objetivo, src.FechaInicio, src.FechaFin, src.Canales,
        src.CategoriasPromocionadas, src.PorcentajeDescuento, src.CodigoCupon, src.Presupuesto, src.Responsable);
GO

/* 3. T15 + T16 · un evento por fila (desanidar JSON) con su fecha en hora Colombia
      Fechas ISO (yyyy-mm-ddThh:mi:ss, UTC)  -> estilo 126
      Fechas texto (dd/mm/aaaa hh:mm)        -> estilo 103 (se asume UTC, igual que las ISO)
      UTC -> Colombia = UTC-5 */
DROP TABLE IF EXISTS stg.Interaccion_Evento;

SELECT i.InteraccionID,
       LOWER(TRIM(j.tipo)) AS TipoEvento,
       j.fecha             AS FechaOriginal,
       DATEADD(HOUR, -5,
           CASE WHEN j.fecha LIKE N'[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]%'
                THEN TRY_CONVERT(DATETIME2, j.fecha, 103)
                ELSE TRY_CONVERT(DATETIME2, j.fecha, 126) END) AS FechaColombia
INTO stg.Interaccion_Evento
FROM stg.mongo_interacciones i
CROSS APPLY OPENJSON(i.EventosJSON) WITH (tipo NVARCHAR(50) '$.tipo', fecha NVARCHAR(50) '$.fecha') j;

CREATE INDEX IX_Interaccion_Evento ON stg.Interaccion_Evento (InteraccionID, TipoEvento);
GO

/* 4. T15 + T17 · FACT_InteraccionMarketing (una fila por interaccion)
      Banderas 0/1 por tipo de evento ('leido' cuenta como Abierto).
      HorasHastaApertura = primera apertura - primer enviado/entregado (si no, NULL).
      TiempoKey = fecha (Colombia) del primer evento.
      T17: clienteId que no existe en DIM_Cliente -> ClienteKey = -1. */
TRUNCATE TABLE dbo.FACT_InteraccionMarketing;

;WITH ev AS (
    SELECT InteraccionID,
        MAX(CASE WHEN TipoEvento = N'enviado'    THEN 1 ELSE 0 END) AS Enviado,
        MAX(CASE WHEN TipoEvento = N'entregado'  THEN 1 ELSE 0 END) AS Entregado,
        MAX(CASE WHEN TipoEvento = N'rebotado'   THEN 1 ELSE 0 END) AS Rebotado,
        MAX(CASE WHEN TipoEvento IN (N'abierto', N'leido') THEN 1 ELSE 0 END) AS Abierto,
        MAX(CASE WHEN TipoEvento = N'impresion'  THEN 1 ELSE 0 END) AS Impresion,
        MAX(CASE WHEN TipoEvento = N'clic'       THEN 1 ELSE 0 END) AS Clic,
        MAX(CASE WHEN TipoEvento = N'baja_suscripcion' THEN 1 ELSE 0 END) AS BajaSuscripcion,
        MIN(FechaColombia) AS FechaPrimerEvento,
        MIN(CASE WHEN TipoEvento IN (N'enviado', N'entregado') THEN FechaColombia END) AS FechaEnvio,
        MIN(CASE WHEN TipoEvento IN (N'abierto', N'leido')     THEN FechaColombia END) AS FechaApertura
    FROM stg.Interaccion_Evento
    GROUP BY InteraccionID
)
INSERT INTO dbo.FACT_InteraccionMarketing
    (TiempoKey, ClienteKey, CampanaKey, CanalMarketingKey, InteraccionID, Dispositivo,
     Enviado, Entregado, Rebotado, Abierto, Impresion, Clic, BajaSuscripcion, CuponRedimido, HorasHastaApertura)
SELECT ISNULL(t.TiempoKey, -1),
       ISNULL(c.ClienteKey, -1),
       ISNULL(ca.CampanaKey, -1),
       ISNULL(cm.CanalMarketingKey, -1),
       i.InteraccionID,
       COALESCE(NULLIF(TRIM(i.Dispositivo), N''), N'Desconocido'),
       ISNULL(e.Enviado, 0), ISNULL(e.Entregado, 0), ISNULL(e.Rebotado, 0), ISNULL(e.Abierto, 0),
       ISNULL(e.Impresion, 0), ISNULL(e.Clic, 0), ISNULL(e.BajaSuscripcion, 0),
       CASE WHEN LOWER(TRIM(i.CuponRedimido)) = N'true' THEN 1 ELSE 0 END,
       CASE WHEN e.FechaApertura IS NOT NULL AND COALESCE(e.FechaEnvio, e.FechaPrimerEvento) <= e.FechaApertura
            THEN CAST(DATEDIFF(SECOND, COALESCE(e.FechaEnvio, e.FechaPrimerEvento), e.FechaApertura) / 3600.0 AS DECIMAL(9,2))
            END
FROM stg.mongo_interacciones i
LEFT JOIN ev e                    ON e.InteraccionID = i.InteraccionID
LEFT JOIN dbo.DIM_Tiempo t        ON t.TiempoKey = CONVERT(INT, FORMAT(e.FechaPrimerEvento, 'yyyyMMdd'))
LEFT JOIN dbo.DIM_Cliente c       ON c.ClienteID = TRY_CAST(TRIM(i.ClienteID) AS INT) AND c.ClienteKey <> -1
LEFT JOIN dbo.DIM_Campana ca      ON ca.CampanaID = TRIM(i.CampanaID) AND ca.CampanaKey <> -1
LEFT JOIN dbo.DIM_CanalMarketing cm ON cm.CanalMarketingID = LOWER(TRIM(i.Canal)) AND cm.CanalMarketingKey <> -1;
GO

/* Comprobaciones (captura) */
SELECT N'DIM_Campana (sin -1)' AS Tabla, COUNT(*) AS Filas FROM dbo.DIM_Campana WHERE CampanaKey <> -1
UNION ALL SELECT N'FACT_InteraccionMarketing', COUNT(*) FROM dbo.FACT_InteraccionMarketing
UNION ALL SELECT N'  con cupón redimido', COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE CuponRedimido = 1
UNION ALL SELECT N'  con clic', COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE Clic = 1
UNION ALL SELECT N'  con ClienteKey = -1 (T17)', COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE ClienteKey = -1;

SELECT CampanaID, NombreCampana, PorcentajeDescuento, Presupuesto, Responsable
FROM dbo.DIM_Campana WHERE CampanaKey <> -1 ORDER BY CampanaID;
GO
PRINT N'T15-T18: carga de marketing terminada.';
GO
