/* =====================================================================
   Data Warehouse en estrella: FINALBI_DW_GrupoN
   Re-ejecutable: borra y recrea la base completa.
   ===================================================================== */
USE master;
GO
IF DB_ID(N'FINALBI_DW_GrupoN') IS NOT NULL
BEGIN
    ALTER DATABASE FINALBI_DW_GrupoN SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE FINALBI_DW_GrupoN;
END
GO
CREATE DATABASE FINALBI_DW_GrupoN;
GO
USE FINALBI_DW_GrupoN;
GO

/* ---------------------------------------------------------------------
   DIMENSIONES
   Convencion: <Dim>Key = clave sustituta; <Natural> = clave del origen;
   fila -1 = miembro desconocido.
   --------------------------------------------------------------------- */

/* DIM_Tiempo (conformada). Clave sustituta = yyyymmdd (INT), -1 = desconocido.*/
CREATE TABLE dbo.DIM_Tiempo (
    TiempoKey        INT          NOT NULL CONSTRAINT PK_DIM_Tiempo PRIMARY KEY,
    Fecha            DATE         NOT NULL CONSTRAINT UQ_DIM_Tiempo_Fecha UNIQUE, -- clave natural
    Anio             SMALLINT     NOT NULL,
    Trimestre        TINYINT      NOT NULL,
    NombreTrimestre  NVARCHAR(20) NOT NULL,  
    Mes              TINYINT      NOT NULL,
    NombreMes        NVARCHAR(20) NOT NULL, 
    AnioMes          INT          NOT NULL,  
    Dia              TINYINT      NOT NULL,
    DiaSemana        TINYINT      NOT NULL,  
    NombreDia        NVARCHAR(20) NOT NULL,  
    SemanaAnio       TINYINT      NOT NULL,
    EsFinDeSemana    BIT          NOT NULL
);

CREATE TABLE dbo.DIM_Cliente (
    ClienteKey            INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_Cliente PRIMARY KEY,
    ClienteID             INT           NOT NULL CONSTRAINT UQ_DIM_Cliente_ID UNIQUE, 
    TipoDocumento         NVARCHAR(3)   NOT NULL,  
    NumeroDocumento       NVARCHAR(20)  NOT NULL,  
    TipoCliente           NVARCHAR(20)  NOT NULL,  
    NombreCompleto        NVARCHAR(210) NOT NULL,  
    Genero                NVARCHAR(20)  NOT NULL, 
    FechaNacimiento       DATE          NULL,
    Edad                  SMALLINT      NULL,      
    RangoEdad             NVARCHAR(20)  NOT NULL,  
    Segmento              NVARCHAR(40)  NOT NULL,  
    FechaRegistro         DATE          NULL,
    Ciudad                NVARCHAR(60)  NOT NULL,
    Departamento          NVARCHAR(60)  NOT NULL,
    Region                NVARCHAR(60)  NOT NULL,
    Pais                  NVARCHAR(60)  NOT NULL,
    NivelFidelizacion     NVARCHAR(20) NOT NULL,  
    PuntosFidelizacion    INT           NOT NULL, 
    CanalPreferido        NVARCHAR(20) NOT NULL,
    OrigenRegistro        NVARCHAR(20)  NOT NULL,  
    Intereses             NVARCHAR(100) NOT NULL,  
    AceptaEmail           BIT           NOT NULL,
    AceptaSMS             BIT           NOT NULL,
    AceptaWhatsApp        BIT           NOT NULL,
    NPSPromedio           DECIMAL(4,2)  NULL,      
    TipoNPS               NVARCHAR(20)  NOT NULL,  
    TienePerfilMarketing  BIT           NOT NULL
);

CREATE TABLE dbo.DIM_Producto (
    ProductoKey     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_Producto PRIMARY KEY,
    ProductoID      INT           NOT NULL CONSTRAINT UQ_DIM_Producto_ID UNIQUE, -- natural
    SKU             NVARCHAR(20)  NOT NULL,
    NombreProducto  NVARCHAR(150) NOT NULL,
    Subcategoria    NVARCHAR(50)  NOT NULL,  
    Categoria       NVARCHAR(50)  NOT NULL,  
    Marca           NVARCHAR(50)  NOT NULL, 
    Proveedor       NVARCHAR(120) NOT NULL,  
    CostoUnitario   DECIMAL(12,2) NULL,
    PrecioLista     DECIMAL(12,2) NULL,
    RangoPrecio     NVARCHAR(30)  NOT NULL   
);

CREATE TABLE dbo.DIM_Sucursal (
    SucursalKey     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_Sucursal PRIMARY KEY,
    SucursalID      INT           NOT NULL CONSTRAINT UQ_DIM_Sucursal_ID UNIQUE, 
    NombreSucursal  NVARCHAR(80)  NOT NULL,
    TipoSucursal    NVARCHAR(20)  NOT NULL,  
    FechaApertura   DATE          NULL,
    Ciudad          NVARCHAR(60)  NOT NULL,  
    Departamento    NVARCHAR(60)  NOT NULL,  
    Region          NVARCHAR(60)  NOT NULL,  
    Pais            NVARCHAR(60)  NOT NULL   
);

CREATE TABLE dbo.DIM_CanalVenta (
    CanalVentaKey   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_CanalVenta PRIMARY KEY,
    CanalVentaID    INT           NOT NULL CONSTRAINT UQ_DIM_CanalVenta_ID UNIQUE, 
    NombreCanal     NVARCHAR(40) NOT NULL   
);


CREATE TABLE dbo.DIM_Empleado (
    EmpleadoKey     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_Empleado PRIMARY KEY,
    EmpleadoID      INT           NOT NULL CONSTRAINT UQ_DIM_Empleado_ID UNIQUE, 
    NombreCompleto  NVARCHAR(210) NOT NULL,
    Cargo           NVARCHAR(50)  NULL
);

CREATE TABLE dbo.DIM_Campana (
    CampanaKey              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_Campana PRIMARY KEY,
    CampanaID               NVARCHAR(20) NOT NULL CONSTRAINT UQ_DIM_Campana_ID UNIQUE, 
    NombreCampana           NVARCHAR(100) NOT NULL,
    Objetivo                NVARCHAR(30)  NOT NULL,
    FechaInicio             DATE          NULL,
    FechaFin                DATE          NULL,
    Canales                 NVARCHAR(100) NOT NULL,  
    CategoriasPromocionadas NVARCHAR(150) NOT NULL,
    PorcentajeDescuento     DECIMAL(5,2)  NOT NULL DEFAULT 0,
    CodigoCupon             NVARCHAR(20) NOT NULL,
    Presupuesto             DECIMAL(18,2) NOT NULL DEFAULT 0, 
    Responsable             NVARCHAR(100) NOT NULL   
);

CREATE TABLE dbo.DIM_CanalMarketing (
    CanalMarketingKey  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_CanalMarketing PRIMARY KEY,
    CanalMarketingID   NVARCHAR(20) NOT NULL CONSTRAINT UQ_DIM_CanalMarketing_ID UNIQUE, 
    NombreCanal        NVARCHAR(30) NOT NULL
);
GO

/* ---------------------------------------------------------------------
   MIEMBRO DESCONOCIDO (-1) EN CADA DIMENSION
   --------------------------------------------------------------------- */
INSERT INTO dbo.DIM_Tiempo (TiempoKey, Fecha, Anio, Trimestre, NombreTrimestre, Mes, NombreMes,
                            AnioMes, Dia, DiaSemana, NombreDia, SemanaAnio, EsFinDeSemana)
VALUES (-1, '1900-01-01', 1900, 1, N'Desconocido', 1, N'Desconocido', 190001, 1, 1, N'Desconocido', 1, 0);

SET IDENTITY_INSERT dbo.DIM_Cliente ON;
INSERT INTO dbo.DIM_Cliente (ClienteKey, ClienteID, TipoDocumento, NumeroDocumento, TipoCliente, NombreCompleto, Genero, FechaNacimiento, Edad,
    RangoEdad, Segmento, FechaRegistro, Ciudad, Departamento, Region, Pais, NivelFidelizacion, PuntosFidelizacion,
    CanalPreferido, OrigenRegistro, Intereses, AceptaEmail, AceptaSMS, AceptaWhatsApp, NPSPromedio, TipoNPS, TienePerfilMarketing)
VALUES (-1, -1, N'N/A', N'Desconocido', N'Desconocido', N'Cliente desconocido', N'No aplica', NULL, NULL,
    N'No aplica', N'Desconocido', NULL, N'Desconocido', N'Desconocido', N'Desconocido', N'Desconocido',
    N'Sin programa', 0, N'Desconocido', N'Sin perfil', N'Sin perfil', 0, 0, 0, NULL, N'Sin encuesta', 0);
SET IDENTITY_INSERT dbo.DIM_Cliente OFF;

SET IDENTITY_INSERT dbo.DIM_Producto ON;
INSERT INTO dbo.DIM_Producto (ProductoKey, ProductoID, SKU, NombreProducto, Subcategoria, Categoria, Marca, Proveedor, CostoUnitario, PrecioLista, RangoPrecio)
VALUES (-1, -1, N'N/A', N'Producto desconocido', N'Desconocido', N'Desconocido', N'Desconocido', N'Desconocido', NULL, NULL, N'Desconocido');
SET IDENTITY_INSERT dbo.DIM_Producto OFF;

SET IDENTITY_INSERT dbo.DIM_Sucursal ON;
INSERT INTO dbo.DIM_Sucursal (SucursalKey, SucursalID, NombreSucursal, TipoSucursal, FechaApertura, Ciudad, Departamento, Region, Pais)
VALUES (-1, -1, N'Sucursal desconocida', N'Desconocido', NULL, N'Desconocido', N'Desconocido', N'Desconocido', N'Desconocido');
SET IDENTITY_INSERT dbo.DIM_Sucursal OFF;

SET IDENTITY_INSERT dbo.DIM_CanalVenta ON;
INSERT INTO dbo.DIM_CanalVenta (CanalVentaKey, CanalVentaID, NombreCanal)
VALUES (-1, -1, N'Desconocido');
SET IDENTITY_INSERT dbo.DIM_CanalVenta OFF;

SET IDENTITY_INSERT dbo.DIM_Empleado ON;
INSERT INTO dbo.DIM_Empleado (EmpleadoKey, EmpleadoID, NombreCompleto, Cargo)
VALUES (-1, -1, N'Sin vendedor', NULL);
SET IDENTITY_INSERT dbo.DIM_Empleado OFF;

SET IDENTITY_INSERT dbo.DIM_Campana ON;
INSERT INTO dbo.DIM_Campana (CampanaKey, CampanaID, NombreCampana, Objetivo, FechaInicio, FechaFin, Canales,
    CategoriasPromocionadas, PorcentajeDescuento, CodigoCupon, Presupuesto, Responsable)
VALUES (-1, N'-1', N'Sin campana', N'Desconocido', NULL, NULL, N'Desconocido', N'Desconocido', 0, N'Sin cupon', 0, N'Sin asignar');
SET IDENTITY_INSERT dbo.DIM_Campana OFF;

SET IDENTITY_INSERT dbo.DIM_CanalMarketing ON;
INSERT INTO dbo.DIM_CanalMarketing (CanalMarketingKey, CanalMarketingID, NombreCanal)
VALUES (-1, N'-1', N'Desconocido');
SET IDENTITY_INSERT dbo.DIM_CanalMarketing OFF;


INSERT INTO dbo.DIM_CanalMarketing (CanalMarketingID, NombreCanal)
VALUES (N'email', N'Email'), (N'sms', N'SMS'), (N'whatsapp', N'WhatsApp'), (N'redes_sociales', N'Redes sociales');
GO

/* ---------------------------------------------------------------------
   TABLAS DE HECHOS
   --------------------------------------------------------------------- */

/* FACT_Ventas */
CREATE TABLE dbo.FACT_Ventas (
    VentaKey             BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FACT_Ventas PRIMARY KEY,
    TiempoKey            INT NOT NULL,
    ClienteKey           INT NOT NULL,
    ProductoKey          INT NOT NULL,
    SucursalKey          INT NOT NULL,
    CanalVentaKey        INT NOT NULL,
    EmpleadoKey          INT NOT NULL,  
    CampanaAtribuidaKey  INT NOT NULL CONSTRAINT DF_FV_Camp DEFAULT (-1),  
    NumeroPedido         VARCHAR(20) NOT NULL,  
    DetalleID            INT NOT NULL CONSTRAINT UQ_FACT_Ventas_Detalle UNIQUE, 
    MetodoPagoPrincipal  NVARCHAR(40) NOT NULL,  
    Cantidad             INT           NOT NULL,
    PrecioUnit           DECIMAL(12,2) NOT NULL,
    PorcentajeDescuento  DECIMAL(5,2)  NOT NULL,  
    CostoUnit            DECIMAL(12,2) NOT NULL,
    VentaBruta           DECIMAL(18,2) NOT NULL,
    ValorDescuento       DECIMAL(18,2) NOT NULL,
    TotalVenta           DECIMAL(18,2) NOT NULL,
    CostoTotal           DECIMAL(18,2) NOT NULL,
    Margen               DECIMAL(18,2) NOT NULL,
    CONSTRAINT FK_FV_Tiempo   FOREIGN KEY (TiempoKey)           REFERENCES dbo.DIM_Tiempo(TiempoKey),
    CONSTRAINT FK_FV_Cliente  FOREIGN KEY (ClienteKey)          REFERENCES dbo.DIM_Cliente(ClienteKey),
    CONSTRAINT FK_FV_Producto FOREIGN KEY (ProductoKey)         REFERENCES dbo.DIM_Producto(ProductoKey),
    CONSTRAINT FK_FV_Sucursal FOREIGN KEY (SucursalKey)         REFERENCES dbo.DIM_Sucursal(SucursalKey),
    CONSTRAINT FK_FV_Canal    FOREIGN KEY (CanalVentaKey)       REFERENCES dbo.DIM_CanalVenta(CanalVentaKey),
    CONSTRAINT FK_FV_Empleado FOREIGN KEY (EmpleadoKey)         REFERENCES dbo.DIM_Empleado(EmpleadoKey),
    CONSTRAINT FK_FV_Campana  FOREIGN KEY (CampanaAtribuidaKey) REFERENCES dbo.DIM_Campana(CampanaKey)
);

/* FACT_InteraccionMarketing
   Granularidad: una fila por interaccion cliente-campana
 */
CREATE TABLE dbo.FACT_InteraccionMarketing (
    InteraccionKey     BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FACT_Interaccion PRIMARY KEY,
    TiempoKey          INT NOT NULL,   
    ClienteKey         INT NOT NULL,   
    CampanaKey         INT NOT NULL,
    CanalMarketingKey  INT NOT NULL,
    InteraccionID      NVARCHAR(24) NOT NULL CONSTRAINT UQ_FACT_Interaccion_ID UNIQUE,  
    Dispositivo        NVARCHAR(20) NOT NULL,   
    Enviado            TINYINT NOT NULL,
    Entregado          TINYINT NOT NULL,
    Rebotado           TINYINT NOT NULL,
    Abierto            TINYINT NOT NULL,  
    Impresion          TINYINT NOT NULL, 
    Clic               TINYINT NOT NULL,
    BajaSuscripcion    TINYINT NOT NULL,
    CuponRedimido      TINYINT NOT NULL,
    HorasHastaApertura DECIMAL(9,2) NULL,  
    CONSTRAINT CK_FIM_Flags CHECK (Enviado IN (0,1) AND Entregado IN (0,1) AND Rebotado IN (0,1)
        AND Abierto IN (0,1) AND Impresion IN (0,1) AND Clic IN (0,1) AND BajaSuscripcion IN (0,1) AND CuponRedimido IN (0,1)),
    CONSTRAINT FK_FIM_Tiempo   FOREIGN KEY (TiempoKey)         REFERENCES dbo.DIM_Tiempo(TiempoKey),
    CONSTRAINT FK_FIM_Cliente  FOREIGN KEY (ClienteKey)        REFERENCES dbo.DIM_Cliente(ClienteKey),
    CONSTRAINT FK_FIM_Campana  FOREIGN KEY (CampanaKey)        REFERENCES dbo.DIM_Campana(CampanaKey),
    CONSTRAINT FK_FIM_Canal    FOREIGN KEY (CanalMarketingKey) REFERENCES dbo.DIM_CanalMarketing(CanalMarketingKey)
);
GO

/* Indices sobre las claves foraneas (consultas de Power BI) */
CREATE INDEX IX_FV_Tiempo   ON dbo.FACT_Ventas (TiempoKey);
CREATE INDEX IX_FV_Cliente  ON dbo.FACT_Ventas (ClienteKey);
CREATE INDEX IX_FV_Producto ON dbo.FACT_Ventas (ProductoKey);
CREATE INDEX IX_FV_Sucursal ON dbo.FACT_Ventas (SucursalKey);
CREATE INDEX IX_FV_Canal    ON dbo.FACT_Ventas (CanalVentaKey);
CREATE INDEX IX_FV_Campana  ON dbo.FACT_Ventas (CampanaAtribuidaKey);
CREATE INDEX IX_FV_Pedido   ON dbo.FACT_Ventas (NumeroPedido);
CREATE INDEX IX_FIM_Tiempo  ON dbo.FACT_InteraccionMarketing (TiempoKey);
CREATE INDEX IX_FIM_Cliente ON dbo.FACT_InteraccionMarketing (ClienteKey);
CREATE INDEX IX_FIM_Campana ON dbo.FACT_InteraccionMarketing (CampanaKey);
CREATE INDEX IX_FIM_Canal   ON dbo.FACT_InteraccionMarketing (CanalMarketingKey);
GO

PRINT 'DW creado: dimensiones con miembro -1 y tablas de hechos listas.';
GO


/* =====================================================================
   NOTA: T9 - Calendario: carga de DIM_Tiempo
   Genera un dia por fila, continuo, con anios completos (2024 y 2025),
   con nombres en espanol que NO dependen del idioma ni del DATEFIRST del servidor.
   Requiere: 01_Crear_DW.sql ya ejecutado (la tabla y la fila -1 ya existen).
   Re-ejecutable: solo inserta los dias que faltan; no borra nada ni toca la fila -1.
   ===================================================================== */