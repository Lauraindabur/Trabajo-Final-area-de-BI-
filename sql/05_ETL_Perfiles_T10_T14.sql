/* =====================================================================
   PARTE 3 · ETL de perfiles_marketing: T10, T11, T12, T13 y T14 (Persona 2)

   Orden de ejecución:
     1. FINALBI_DW_GrupoN.sql           (crea el DW)
     2. P2_01_stg_perfiles.sql          (crea el staging de perfiles)
     3. python extraer_perfiles_mongo.py  (MongoDB -> stg.PerfilesMarketing)
     4. Carga de DIM_Cliente desde el OLTP (T1-T4, Persona 1 / Persona 4)
     5. ESTE SCRIPT: limpia los perfiles y enriquece DIM_Cliente

   Re-ejecutable: recrea stg.PerfilCliente y vuelve a escribir las columnas
   de mercadeo de DIM_Cliente; da el mismo resultado cada vez.

   Resultado:
     stg.PerfilCliente  1 fila por cliente, ya limpia (contrato con DIM_Cliente)
     DIM_Cliente        columnas de mercadeo llenas (NivelFidelizacion, Puntos,
                        CanalPreferido, Acepta*, Intereses, NPSPromedio, TipoNPS,
                        OrigenRegistro, TienePerfilMarketing)
     dbo.ReporteCalidadDatos  filas de la fuente "Mongo · perfiles"
   ===================================================================== */
USE FINALBI_DW_GrupoN;
GO
SET NOCOUNT ON;

/* ---------------------------------------------------------------------
   T10 · Tipo de dato: clienteId en texto -> entero
   Se quitan espacios y se convierte con TRY_CAST (si no es número queda NULL
   y se reporta; en estos datos no ocurre).
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #Perfiles;
SELECT p.*,
       TRY_CAST(LTRIM(RTRIM(p.ClienteIdRaw)) AS INT) AS ClienteID
INTO #Perfiles
FROM stg.PerfilesMarketing p;

/* ---------------------------------------------------------------------
   T11 · Duplicados: si un cliente tiene varios perfiles se conserva el de
   fechaActualizacion más reciente (empate: el último cargado).
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #PerfilVigente;
SELECT *
INTO #PerfilVigente
FROM (
    SELECT p.*,
           ROW_NUMBER() OVER (PARTITION BY p.ClienteID
                              ORDER BY p.FechaActualizacionUTC DESC, p.FilaID DESC) AS rn
    FROM #Perfiles p
    WHERE p.ClienteID IS NOT NULL
) x
WHERE x.rn = 1;

/* ---------------------------------------------------------------------
   T12 · Estandarización de intereses a las 6 categorías oficiales del OLTP
   Se compara sin mayúsculas ni tildes (collation CI_AI), sin espacios y
   aceptando el singular ("Deporte" -> Deportes). Lo que no coincide va a
   "Otro" y se reporta.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #Intereses;
SELECT v.FilaID, v.ClienteID,
       j.[value]                                   AS InteresOrigen,
       ISNULL(c.Nombre, N'Otro')                   AS Categoria
INTO #Intereses
FROM #PerfilVigente v
CROSS APPLY OPENJSON(v.InteresesJSON) j
OUTER APPLY (
    SELECT TOP (1) cat.Nombre
    FROM FINALBI_OLTP.dbo.Categorias cat
    WHERE LTRIM(RTRIM(j.[value])) COLLATE Latin1_General_CI_AI = cat.Nombre COLLATE Latin1_General_CI_AI
       OR LTRIM(RTRIM(j.[value])) + N's' COLLATE Latin1_General_CI_AI = cat.Nombre COLLATE Latin1_General_CI_AI
) c;

DROP TABLE IF EXISTS #InteresesCliente;
SELECT d.ClienteID,
       STRING_AGG(d.Categoria, N', ') WITHIN GROUP (ORDER BY d.Categoria) AS Intereses
INTO #InteresesCliente
FROM (SELECT DISTINCT ClienteID, Categoria FROM #Intereses) d
GROUP BY d.ClienteID;

/* ---------------------------------------------------------------------
   T14 · Desanidar encuestasNPS y agregar por cliente
   NPSPromedio = promedio de puntajes; clasificación del promedio:
   Promotor >= 9 · Pasivo >= 7 y < 9 · Detractor < 7 · sin encuestas = "Sin encuesta"
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #Encuestas;
SELECT v.ClienteID, e.puntaje, e.fecha
INTO #Encuestas
FROM #PerfilVigente v
CROSS APPLY OPENJSON(v.EncuestasNPSJSON)
     WITH (puntaje INT '$.puntaje', fecha NVARCHAR(30) '$.fecha') e
WHERE e.puntaje BETWEEN 0 AND 10;

DROP TABLE IF EXISTS #NPSCliente;
SELECT ClienteID,
       COUNT(*)                                             AS NumEncuestas,
       CAST(AVG(CAST(puntaje AS DECIMAL(6,2))) AS DECIMAL(4,2)) AS NPSPromedio
INTO #NPSCliente
FROM #Encuestas
GROUP BY ClienteID;

/* ---------------------------------------------------------------------
   Perfil limpio: 1 fila por cliente (incluye T13)
   T13 · Sin fidelizacion -> "Sin programa" y 0 puntos; puntos en texto -> entero
   Adicional A1 · canal preferido sin consentimiento para ese canal -> "Ninguno"
                  (no se le puede escribir por ese canal: Ley 1581)
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS stg.PerfilCliente;
SELECT
    v.ClienteID,
    v.MongoID,
    v.FechaActualizacionUTC,
    CASE LOWER(LTRIM(RTRIM(v.OrigenRegistro)))
         WHEN N'tienda' THEN N'Tienda' WHEN N'web' THEN N'Web'
         WHEN N'app' THEN N'App'       WHEN N'referido' THEN N'Referido'
         ELSE N'Desconocido' END                                         AS OrigenRegistro,
    ISNULL(v.ConsEmail, 0)                                               AS AceptaEmail,
    ISNULL(v.ConsSMS, 0)                                                 AS AceptaSMS,
    ISNULL(v.ConsWhatsApp, 0)                                            AS AceptaWhatsApp,
    CASE
        WHEN LOWER(v.CanalPreferido) = N'email'    AND ISNULL(v.ConsEmail, 0) = 1    THEN N'Email'
        WHEN LOWER(v.CanalPreferido) = N'sms'      AND ISNULL(v.ConsSMS, 0) = 1      THEN N'SMS'
        WHEN LOWER(v.CanalPreferido) = N'whatsapp' AND ISNULL(v.ConsWhatsApp, 0) = 1 THEN N'WhatsApp'
        ELSE N'Ninguno' END                                              AS CanalPreferido,
    CAST(CASE WHEN LOWER(v.CanalPreferido) IN (N'email', N'sms', N'whatsapp')
               AND CASE LOWER(v.CanalPreferido) WHEN N'email' THEN v.ConsEmail
                                                WHEN N'sms' THEN v.ConsSMS
                                                ELSE v.ConsWhatsApp END = 0
              THEN 1 ELSE 0 END AS BIT)                                  AS CanalSinConsentimiento,
    ISNULL(i.Intereses, N'Sin intereses')                                AS Intereses,
    CASE WHEN v.TieneFidelizacion = 1 AND v.FidNivel IS NOT NULL
         THEN LTRIM(RTRIM(v.FidNivel)) ELSE N'Sin programa' END          AS NivelFidelizacion,
    CASE WHEN v.TieneFidelizacion = 1
         THEN ISNULL(TRY_CAST(REPLACE(REPLACE(LTRIM(RTRIM(v.FidPuntosRaw)), N'.', N''), N',', N'') AS INT), 0)
         ELSE 0 END                                                      AS PuntosFidelizacion,
    ISNULL(n.NumEncuestas, 0)                                            AS NumEncuestasNPS,
    n.NPSPromedio,
    CASE WHEN n.NPSPromedio IS NULL THEN N'Sin encuesta'
         WHEN n.NPSPromedio >= 9    THEN N'Promotor'
         WHEN n.NPSPromedio >= 7    THEN N'Pasivo'
         ELSE N'Detractor' END                                           AS TipoNPS
INTO stg.PerfilCliente
FROM #PerfilVigente v
LEFT JOIN #InteresesCliente i ON i.ClienteID = v.ClienteID
LEFT JOIN #NPSCliente       n ON n.ClienteID = v.ClienteID;

ALTER TABLE stg.PerfilCliente ALTER COLUMN ClienteID INT NOT NULL;
ALTER TABLE stg.PerfilCliente ADD CONSTRAINT PK_stg_PerfilCliente PRIMARY KEY (ClienteID);

/* ---------------------------------------------------------------------
   Enriquecer DIM_Cliente (clave natural ClienteID = clienteId de MongoDB)
   Clientes con perfil -> datos de stg.PerfilCliente
   Clientes sin perfil -> valores por defecto y TienePerfilMarketing = 0
   El miembro -1 no se toca.
   --------------------------------------------------------------------- */
UPDATE d SET
    d.NivelFidelizacion    = ISNULL(p.NivelFidelizacion, N'Sin programa'),
    d.PuntosFidelizacion   = ISNULL(p.PuntosFidelizacion, 0),
    d.CanalPreferido       = ISNULL(p.CanalPreferido, N'Sin perfil'),
    d.OrigenRegistro       = ISNULL(p.OrigenRegistro, N'Sin perfil'),
    d.Intereses            = ISNULL(p.Intereses, N'Sin perfil'),
    d.AceptaEmail          = ISNULL(p.AceptaEmail, 0),
    d.AceptaSMS            = ISNULL(p.AceptaSMS, 0),
    d.AceptaWhatsApp       = ISNULL(p.AceptaWhatsApp, 0),
    d.NPSPromedio          = p.NPSPromedio,
    d.TipoNPS              = ISNULL(p.TipoNPS, N'Sin encuesta'),
    d.TienePerfilMarketing = CASE WHEN p.ClienteID IS NULL THEN 0 ELSE 1 END
FROM dbo.DIM_Cliente d
LEFT JOIN stg.PerfilCliente p ON p.ClienteID = d.ClienteID
WHERE d.ClienteKey <> -1;

/* ---------------------------------------------------------------------
   Reporte de calidad (Parte 4): una fila por problema de perfiles
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ReporteCalidadDatos') IS NULL
CREATE TABLE dbo.ReporteCalidadDatos (
    ReporteID          INT IDENTITY(1,1) PRIMARY KEY,
    Fuente             NVARCHAR(40)  NOT NULL,
    Transformacion     NVARCHAR(10)  NOT NULL,
    Problema           NVARCHAR(200) NOT NULL,
    RegistrosAfectados INT           NOT NULL,
    ReglaAplicada      NVARCHAR(300) NOT NULL,
    FechaEjecucion     DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
DELETE FROM dbo.ReporteCalidadDatos WHERE Fuente = N'Mongo · perfiles';

INSERT INTO dbo.ReporteCalidadDatos (Fuente, Transformacion, Problema, RegistrosAfectados, ReglaAplicada)
SELECT N'Mongo · perfiles', N'T10', N'clienteId guardado como texto',
       (SELECT COUNT(*) FROM stg.PerfilesMarketing WHERE ClienteIdTipoOrigen = N'string'),
       N'TRY_CAST(TRIM(clienteId) AS INT)'
UNION ALL
SELECT N'Mongo · perfiles', N'T10', N'clienteId que no se pudo convertir a número',
       (SELECT COUNT(*) FROM #Perfiles WHERE ClienteID IS NULL),
       N'Se descarta el perfil (no se puede unir a ningún cliente)'
UNION ALL
SELECT N'Mongo · perfiles', N'T11', N'Perfiles duplicados del mismo cliente (filas descartadas)',
       (SELECT COUNT(*) FROM #Perfiles WHERE ClienteID IS NOT NULL) - (SELECT COUNT(*) FROM #PerfilVigente),
       N'Se conserva el perfil con fechaActualizacion más reciente (ROW_NUMBER)'
UNION ALL
SELECT N'Mongo · perfiles', N'T12', N'Intereses mal escritos (mayúsculas, tildes, espacios o singular)',
       (SELECT COUNT(*) FROM #Intereses WHERE InteresOrigen COLLATE Latin1_General_BIN <> Categoria COLLATE Latin1_General_BIN),
       N'Comparación sin mayúsculas ni tildes (CI_AI), TRIM y singular -> 6 categorías del OLTP'
UNION ALL
SELECT N'Mongo · perfiles', N'T12', N'Intereses que no corresponden a ninguna categoría',
       (SELECT COUNT(*) FROM #Intereses WHERE Categoria = N'Otro'),
       N'Se clasifican como "Otro"'
UNION ALL
SELECT N'Mongo · perfiles', N'T13', N'Perfiles sin objeto fidelizacion',
       (SELECT COUNT(*) FROM #PerfilVigente WHERE TieneFidelizacion = 0),
       N'NivelFidelizacion = "Sin programa" y PuntosFidelizacion = 0'
UNION ALL
SELECT N'Mongo · perfiles', N'T13', N'Puntos de fidelización guardados como texto',
       (SELECT COUNT(*) FROM #PerfilVigente WHERE FidPuntosTipoOrigen = N'string'),
       N'TRY_CAST(puntos AS INT); si no convierte -> 0'
UNION ALL
SELECT N'Mongo · perfiles', N'T14', N'Perfiles sin encuestas NPS (arreglo ausente)',
       (SELECT COUNT(*) FROM stg.PerfilCliente WHERE NumEncuestasNPS = 0),
       N'NPSPromedio = NULL y TipoNPS = "Sin encuesta"'
UNION ALL
SELECT N'Mongo · perfiles', N'T14', N'Encuestas NPS anidadas desanidadas con OPENJSON',
       (SELECT COUNT(*) FROM #Encuestas),
       N'Promedio por cliente; Promotor >= 9, Pasivo 7-8, Detractor 0-6'
UNION ALL
SELECT N'Mongo · perfiles', N'A1', N'Canal preferido sin consentimiento para ese canal (en origen)',
       (SELECT COUNT(*) FROM #Perfiles
        WHERE (LOWER(CanalPreferido) = N'email' AND ConsEmail = 0)
           OR (LOWER(CanalPreferido) = N'sms' AND ConsSMS = 0)
           OR (LOWER(CanalPreferido) = N'whatsapp' AND ConsWhatsApp = 0)),
       CONCAT(N'CanalPreferido = "Ninguno" (Ley 1581). Quedan en el perfil vigente: ',
              (SELECT COUNT(*) FROM stg.PerfilCliente WHERE CanalSinConsentimiento = 1),
              N' (el resto eran perfiles viejos eliminados por T11)')
UNION ALL
SELECT N'Mongo · perfiles', N'INT', N'clienteId que no existe en el OLTP',
       (SELECT COUNT(*) FROM stg.PerfilCliente p WHERE NOT EXISTS (SELECT 1 FROM dbo.DIM_Cliente d WHERE d.ClienteID = p.ClienteID)),
       N'No se cargan en DIM_Cliente (no hay cliente al cual enriquecer)';
GO

PRINT 'Perfiles: T10-T14 aplicadas y DIM_Cliente enriquecida.';
SELECT Transformacion, Problema, RegistrosAfectados, ReglaAplicada
FROM dbo.ReporteCalidadDatos WHERE Fuente = N'Mongo · perfiles' ORDER BY ReporteID;
GO
