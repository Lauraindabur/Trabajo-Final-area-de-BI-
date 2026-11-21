/* =====================================================================
   PARTE 3 · Staging de perfiles_marketing (Persona 2)
   Requiere: FINALBI_DW_GrupoN ya creada.
   Re-ejecutable: borra y recrea las tablas stg de perfiles.

   QUE HACEMOS: crea dos tablas vacías donde Python va a dejar los perfiles de Mongo. No mueve datos todavía. 
   Las columnas están diseñadas para guardar el dato tal como viene, aunque venga mal

   stg.PerfilesMarketing   copia CRUDA de MongoDB (1 fila por documento,
                           sin limpiar: el clienteId y los puntos llegan
                           como texto, los arreglos como JSON).
   stg.ControlExtraccion   cuántos documentos había en MongoDB al extraer
                           (lo usa la validación de la Parte 4).
   ===================================================================== */
USE FINALBI_DW_GrupoN;
GO
IF SCHEMA_ID(N'stg') IS NULL EXEC (N'CREATE SCHEMA stg');
GO

DROP TABLE IF EXISTS stg.PerfilCliente;      -- la crea el script P2_02
DROP TABLE IF EXISTS stg.PerfilesMarketing;
CREATE TABLE stg.PerfilesMarketing ( -- Crea stg.PerfilesMarketing: la copia cruda de la colección perfiles_marketing de Mongo.
    FilaID               INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_stg_PerfilesMarketing PRIMARY KEY,
    MongoID              NVARCHAR(24)   NOT NULL,   -- _id del documento
    ClienteIdRaw         NVARCHAR(20)   NULL,       -- tal cual: número o texto
    ClienteIdTipoOrigen  NVARCHAR(10)   NULL,       -- int / string (evidencia de T10)
    FechaActualizacionUTC DATETIME2(0)  NULL,
    OrigenRegistro       NVARCHAR(20)   NULL,
    ConsEmail            BIT            NULL,
    ConsSMS              BIT            NULL,
    ConsWhatsApp         BIT            NULL,
    CanalPreferido       NVARCHAR(20)   NULL,
    InteresesJSON        NVARCHAR(400)  NULL,       -- arreglo tal cual, ej. ["Ropa ","DEPORTES"]
    TieneFidelizacion    BIT            NOT NULL,
    FidNivel             NVARCHAR(20)   NULL,
    FidPuntosRaw         NVARCHAR(20)   NULL,       -- tal cual: número o texto
    FidPuntosTipoOrigen  NVARCHAR(10)   NULL,       -- int / string (evidencia de T13)
    FidFechaInscripcionUTC DATETIME2(0) NULL,
    EncuestasNPSJSON     NVARCHAR(MAX)  NULL,       -- arreglo tal cual, ej. [{"puntaje":8,...}]
    FechaCarga           DATETIME2(0)   NOT NULL CONSTRAINT DF_stg_PM_Carga DEFAULT SYSDATETIME()
);

IF OBJECT_ID(N'stg.ControlExtraccion') IS NULL -- una tabla de control que anota cuántos documentos había en Mongo y cuántos se cargaron.
CREATE TABLE stg.ControlExtraccion (
    Coleccion          NVARCHAR(60) NOT NULL CONSTRAINT PK_stg_ControlExtraccion PRIMARY KEY,
    DocumentosOrigen   INT          NOT NULL,
    FilasCargadasStg   INT          NOT NULL,
    FechaExtraccion    DATETIME2(0) NOT NULL
);
GO
PRINT 'Staging de perfiles listo. Siguiente: python extraer_perfiles_mongo.py';
