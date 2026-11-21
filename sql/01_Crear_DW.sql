
/* =====================================================================
   Data Warehouse en estrella: FINALBI_DW_GrupoN
   Re-ejecutable: borra y recrea la base completa.
   ===================================================================== */
USE master;
GO  /*  Separa bloques de instrucciones es mas que todo para SSMS y sqlcmd*/
IF DB_ID(N'FINALBI_DW_GrupoN') IS NOT NULL /*  Revisa si ya existe */
BEGIN
    ALTER DATABASE FINALBI_DW_GrupoN SET SINGLE_USER WITH ROLLBACK IMMEDIATE;  /* Deja la bd para un solo usuario y cierra otras conexiones abiertas -> sino falla la que se esta creando */
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
/* T9: esta tabla se llena con un script que genera cada dia de 2024 y 2025
   (anios completos), con nombres en espanol que no dependan del idioma del servidor. */
CREATE TABLE dbo.DIM_Tiempo (
    TiempoKey        INT          NOT NULL CONSTRAINT PK_DIM_Tiempo PRIMARY KEY,   /* clave sustituta -> CONSTRAINT le pone nombre a la regla -> id que usan los hechos*/
    Fecha            DATE         NOT NULL CONSTRAINT UQ_DIM_Tiempo_Fecha UNIQUE, -- clave natural ->regla extra para que otra columna no se repita -> id del oltp
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

/* DIM_Cliente: la llenan DOS personas sobre la misma fila (join por ClienteID).
    aporta lo del OLTP, aporta lo de MongoDB, 
    Cada fila de DIM_Cliente es un cliente, y se junta por ClienteID.
    . */
CREATE TABLE dbo.DIM_Cliente (
    ClienteKey            INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_Cliente PRIMARY KEY, -- tabla sustituta
    ClienteID             INT           NOT NULL CONSTRAINT UQ_DIM_Cliente_ID UNIQUE,  -- clave natural; Clientes.ClienteID del OLTP y el clienteId de Mongo, la que une las dos fuentes. El comentario recuerda T10: en Mongo a veces venía como texto y se convierte a entero
    TipoDocumento         NVARCHAR(3)   NOT NULL,  -- OLTP
    NumeroDocumento       NVARCHAR(20)  NOT NULL,  -- OLTP
    TipoCliente           NVARCHAR(20)  NOT NULL,  --  Empresa si TipoDocumento = NIT, si no Persona
    NombreCompleto        NVARCHAR(210) NOT NULL,  
    Genero                NVARCHAR(20)  NOT NULL,  -- Femenino/Masculino/No aplica
    FechaNacimiento       DATE          NULL,  --  OLTP
    Edad                  SMALLINT      NULL,  
    RangoEdad             NVARCHAR(20)  NOT NULL,  -- 	18-25, 26-35, etc. o "No aplica"
    Segmento              NVARCHAR(40)  NOT NULL,  -- Persona natural, Pyme o Corporativo
    FechaRegistro         DATE          NULL,  -- Cuándo se registró el cliente
    Ciudad                NVARCHAR(60)  NOT NULL,  -- el OLTP estos datos están repartidos en varias tablas encadenadas (Ciudad → Departamento → Región → País).
    Departamento          NVARCHAR(60)  NOT NULL,  -- Aquí quedan aplanados en una sola tabla
    Region                NVARCHAR(60)  NOT NULL,  --  Lo que hicimos fue desnormalizar (T4)
    Pais                  NVARCHAR(60)  NOT NULL,  
    NivelFidelizacion     NVARCHAR(20) NOT NULL,  -- PARTE DE MONGO T13  Bronce, Plata, Oro, Diamante -> sin fidelizacion = Sin programa
    PuntosFidelizacion    INT           NOT NULL,  -- Puntos acumulados. En Mongo venían a veces como texto y se convierten a entero (T13)
    CanalPreferido        NVARCHAR(20) NOT NULL,  -- Canal por el que prefiere que lo contacten. Se toma del perfil más reciente (T11)
    OrigenRegistro        NVARCHAR(20)  NOT NULL,  -- Por dónde se registró
    Intereses             NVARCHAR(100) NOT NULL,  -- Categorías de interés, ya llevadas a las 6 oficiales (T12)
    AceptaEmail           BIT           NOT NULL,  -- 1 si dio consentimiento para ese cana
    AceptaSMS             BIT           NOT NULL,  -- 
    AceptaWhatsApp        BIT           NOT NULL,  -- 
    NPSPromedio           DECIMAL(4,2)  NULL,  -- Promedio de sus encuestas (T14)
    TipoNPS               NVARCHAR(20)  NOT NULL,  -- Promotor (9-10), Pasivo (7-8), Detractor (0-6)
    TienePerfilMarketing  BIT           NOT NULL  -- 1 si el cliente tiene perfil en Mongo
);


CREATE TABLE dbo.DIM_Producto (
    ProductoKey     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_Producto PRIMARY KEY,
    ProductoID      INT           NOT NULL CONSTRAINT UQ_DIM_Producto_ID UNIQUE, -- natural
    SKU             NVARCHAR(20)  NOT NULL, -- Código interno del producto, texto de hasta 20 caracteres
    NombreProducto  NVARCHAR(150) NOT NULL,
    Subcategoria    NVARCHAR(50)  NOT NULL,  -- CATEGORIA SUBCATEGORIA MARCA Y PROVEEDOR  es por la desnormalizacion de T5
    Categoria       NVARCHAR(50)  NOT NULL,  
    Marca           NVARCHAR(50)  NOT NULL, 
    Proveedor       NVARCHAR(120) NOT NULL,  
    CostoUnitario   DECIMAL(12,2) NULL,  -- admite null para poner la fila -1 costo unitario desconocido
    PrecioLista     DECIMAL(12,2) NULL,
    RangoPrecio     NVARCHAR(30)  NOT NULL   -- Menos de $50.000, de $50.000 a $499.999 o $500.000 o más (T5) 
);

CREATE TABLE dbo.DIM_Sucursal (
    SucursalKey     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_Sucursal PRIMARY KEY,
    SucursalID      INT           NOT NULL CONSTRAINT UQ_DIM_Sucursal_ID UNIQUE, 
    NombreSucursal  NVARCHAR(80)  NOT NULL,
    TipoSucursal    NVARCHAR(20)  NOT NULL,  --"Física" o "Virtual
    FechaApertura   DATE          NULL,   --Vacío para el -1
    Ciudad          NVARCHAR(60)  NOT NULL,  --  T4 geografia desnormalizada -> asi podemos hacer en Power BI "ventas por región"
    Departamento    NVARCHAR(60)  NOT NULL,  --  T4 geografia desnormalizada
    Region          NVARCHAR(60)  NOT NULL,  --  T4 geografia desnormalizada
    Pais            NVARCHAR(60)  NOT NULL  --  T4 geografia desnormalizada
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

-- Dimensiones con datos de mercadeo vienen de mongo
CREATE TABLE dbo.DIM_Campana (
    CampanaKey              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_Campana PRIMARY KEY,
    CampanaID               NVARCHAR(20) NOT NULL CONSTRAINT UQ_DIM_Campana_ID UNIQUE, -- calve natural -> el _id de mongo
    NombreCampana           NVARCHAR(100) NOT NULL, --"Black Friday 2025", "Día de la Madre 2024"
    Objetivo                NVARCHAR(30)  NOT NULL,
    FechaInicio             DATE          NULL,
    FechaFin                DATE          NULL,
    Canales                 NVARCHAR(100) NOT NULL, --email,sms 
    CategoriasPromocionadas NVARCHAR(150) NOT NULL,
    PorcentajeDescuento     DECIMAL(5,2)  NOT NULL DEFAULT 0, -- max 5 dígitos con 2 decimales.
    CodigoCupon             NVARCHAR(20) NOT NULL,
    Presupuesto             DECIMAL(18,2) NOT NULL DEFAULT 0, -- En Mongo venía como texto ("11.700.000") y se convierte a número en T18
    Responsable             NVARCHAR(100) NOT NULL   -- Quién la manejó. Si falta, "Sin asignar" (T18)
);

CREATE TABLE dbo.DIM_CanalMarketing (
    CanalMarketingKey  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DIM_CanalMarketing PRIMARY KEY,
    CanalMarketingID   NVARCHAR(20) NOT NULL CONSTRAINT UQ_DIM_CanalMarketing_ID UNIQUE, 
    NombreCanal        NVARCHAR(30) NOT NULL --Email, SMS, WhatsApp, Redes sociales
);
GO

/* ---------------------------------------------------------------------
    Se inserta la fila "comodín" -1 en cada dimensión y carga los 4 canales de marketing
   --------------------------------------------------------------------- */
INSERT INTO dbo.DIM_Tiempo (TiempoKey, Fecha, Anio, Trimestre, NombreTrimestre, Mes, NombreMes,
                            AnioMes, Dia, DiaSemana, NombreDia, SemanaAnio, EsFinDeSemana)
VALUES (-1, '1900-01-01', 1900, 1, N'Desconocido', 1, N'Desconocido', 190001, 1, 1, N'Desconocido', 1, 0);

SET IDENTITY_INSERT dbo.DIM_Cliente ON; -- La llave sustituta es IDENTITY CON ON  se inserta un valor propio que es -1
INSERT INTO dbo.DIM_Cliente (ClienteKey, ClienteID, TipoDocumento, NumeroDocumento, TipoCliente, NombreCompleto, Genero, FechaNacimiento, Edad,
    RangoEdad, Segmento, FechaRegistro, Ciudad, Departamento, Region, Pais, NivelFidelizacion, PuntosFidelizacion,
    CanalPreferido, OrigenRegistro, Intereses, AceptaEmail, AceptaSMS, AceptaWhatsApp, NPSPromedio, TipoNPS, TienePerfilMarketing)
VALUES (-1, -1, N'N/A', N'Desconocido', N'Desconocido', N'Cliente desconocido', N'No aplica', NULL, NULL, -- -1 de llave sustitua y el segundo de llave natural 
    N'No aplica', N'Desconocido', NULL, N'Desconocido', N'Desconocido', N'Desconocido', N'Desconocido',
    N'Sin programa', 0, N'Desconocido', N'Sin perfil', N'Sin perfil', 0, 0, 0, NULL, N'Sin encuesta', 0);
SET IDENTITY_INSERT dbo.DIM_Cliente OFF; -- se cierra el permiso desde aca a llave vuelve a numerarse sola

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
VALUES (-1, N'-1', N'Desconocido'); -- Se usa N para guardar bien tildes y simbolos 
SET IDENTITY_INSERT dbo.DIM_CanalMarketing OFF;


INSERT INTO dbo.DIM_CanalMarketing (CanalMarketingID, NombreCanal)
VALUES (N'email', N'Email'), (N'sms', N'SMS'), (N'whatsapp', N'WhatsApp'), (N'redes_sociales', N'Redes sociales');
GO

/* ---------------------------------------------------------------------
   TABLAS DE HECHOS
   --------------------------------------------------------------------- */

/* FACT_Ventas */
/* 
Granularidad: una fila por producto vendido en un pedido completado. Un pedido con 3 productos genera 3 filas.
*/
CREATE TABLE dbo.FACT_Ventas (
    VentaKey             BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FACT_Ventas PRIMARY KEY,
    TiempoKey            INT NOT NULL, -- Llaveshacia las 5 dimensiones 
    ClienteKey           INT NOT NULL, -- Responden cuando quien que donde y porque canal
    ProductoKey          INT NOT NULL,
    SucursalKey          INT NOT NULL,
    CanalVentaKey        INT NOT NULL,
    EmpleadoKey          INT NOT NULL,  -- Quién vendió. En ventas web y de la app vale -1 (T8)
    CampanaAtribuidaKey  INT NOT NULL CONSTRAINT DF_FV_Camp DEFAULT (-1), -- Qué campaña originó la venta (T19). si no se indica, queda en -1 ("sin atribución")
    NumeroPedido         VARCHAR(20) NOT NULL,  
    DetalleID            INT NOT NULL CONSTRAINT UQ_FACT_Ventas_Detalle UNIQUE,  --  Es el ID de la línea en el OLTP. UNIQUE evita cargar la misma línea dos veces
    MetodoPagoPrincipal  NVARCHAR(40) NOT NULL,  -- El pago de mayor valor del pedido (T7)
    Cantidad             INT           NOT NULL,
    PrecioUnit           DECIMAL(12,2) NOT NULL, -- Precio al que se vendió cada unidad
    PorcentajeDescuento  DECIMAL(5,2)  NOT NULL,  
    CostoUnit            DECIMAL(12,2) NOT NULL,
    VentaBruta           DECIMAL(18,2) NOT NULL,
    ValorDescuento       DECIMAL(18,2) NOT NULL,
    TotalVenta           DECIMAL(18,2) NOT NULL,
    CostoTotal           DECIMAL(18,2) NOT NULL,
    Margen               DECIMAL(18,2) NOT NULL,
    CONSTRAINT FK_FV_Tiempo   FOREIGN KEY (TiempoKey)           REFERENCES dbo.DIM_Tiempo(TiempoKey), -- las llaves foraneas que garantizan la union de la estrella
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
    InteraccionKey     BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FACT_Interaccion PRIMARY KEY, -- identificador de la tabla
    TiempoKey          INT NOT NULL,    -- las llaves de las 4 dimensiones
    ClienteKey         INT NOT NULL,    -- cuando a quien de que campaña y porque canal
    CampanaKey         INT NOT NULL,
    CanalMarketingKey  INT NOT NULL,
    InteraccionID      NVARCHAR(24) NOT NULL CONSTRAINT UQ_FACT_Interaccion_ID UNIQUE,  -- id del documento de mongo
    Dispositivo        NVARCHAR(20) NOT NULL,   
    Enviado            TINYINT NOT NULL, -- 8 badneras que salen de pivotear el arreglo eventos (t15)
    Entregado          TINYINT NOT NULL,  -- 1 si pasó, 0 si no -> para que se puedan sumar y usar en pbi
    Rebotado           TINYINT NOT NULL,
    Abierto            TINYINT NOT NULL,  
    Impresion          TINYINT NOT NULL, 
    Clic               TINYINT NOT NULL,
    BajaSuscripcion    TINYINT NOT NULL,
    CuponRedimido      TINYINT NOT NULL, 
    HorasHastaApertura DECIMAL(9,2) NULL,   -- Horas entre el envío y la apertura.
    CONSTRAINT CK_FIM_Flags CHECK (Enviado IN (0,1) AND Entregado IN (0,1) AND Rebotado IN (0,1) -- check para que las banderas sean si o si 0 o 1
        AND Abierto IN (0,1) AND Impresion IN (0,1) AND Clic IN (0,1) AND BajaSuscripcion IN (0,1) AND CuponRedimido IN (0,1)),
    CONSTRAINT FK_FIM_Tiempo   FOREIGN KEY (TiempoKey)         REFERENCES dbo.DIM_Tiempo(TiempoKey), -- llaves foraneas
    CONSTRAINT FK_FIM_Cliente  FOREIGN KEY (ClienteKey)        REFERENCES dbo.DIM_Cliente(ClienteKey),
    CONSTRAINT FK_FIM_Campana  FOREIGN KEY (CampanaKey)        REFERENCES dbo.DIM_Campana(CampanaKey),
    CONSTRAINT FK_FIM_Canal    FOREIGN KEY (CanalMarketingKey) REFERENCES dbo.DIM_CanalMarketing(CanalMarketingKey)
);
GO

/* Indices sobre las claves foraneas (consultas de Power BI) */
CREATE INDEX IX_FV_Tiempo   ON dbo.FACT_Ventas (TiempoKey); --Se crean sobre las c.foráneas de los dos hechos (TiempoKey, ClienteKey, ProductoKey...) y sobre NumeroPedido > hacer ams rapido cadda que se cruza un hechp con una dimension
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

PRINT 'DW creado: dimensiones con miembro -1 y tablas de hechos listas.'; -- usado en el log 
GO