/* =====================================================================
   02 · STAGING DESDE SQL SERVER 

  -> Crea el esquema stg (carpeta dentro de una base de datos que agrupa tablas), copia el OLTP (con joins a catalogos) y limpia clientes.
  -> Cada DROP TABLE IF EXISTS: las tablas se borran y se vuelven a crear. Eso es lo que permite correr el ETL desde cero con el mismo resultado.

   REQUISITOS: FINALBI_OLTP poblada y 01_Crear_DW.sql ejecutado.
 

   PARTE E DEL ETL -> Se copian los datos de las fuentes al staging (lugar intermadio antes de limpiarlos), sin cambiarlos
   ===================================================================== */

/* =====================================================================
   SECCIÓN 2 · STAGING: ESQUEMA stg Y EXTRACCIÓN DESDE SQL SERVER
   Copia del OLTP sin transformar (solo joins con catálogos para traer
   nombres). Las tablas se recrean en cada ejecución.
   ===================================================================== */
USE FINALBI_DW_GrupoN;
GO

IF SCHEMA_ID(N'stg') IS NULL EXEC (N'CREATE SCHEMA stg'); -- crea el esquema que es una carpeta para agrupar tablas
GO

/* 2.1 Clientes (con segmento y geografía) */
DROP TABLE IF EXISTS stg.SQL_Clientes;
SELECT c.ClienteID, c.TipoDocumento, c.NumeroDocumento, c.Nombres, c.Apellidos, c.Genero,
       c.FechaNacimiento, c.Email, c.Telefono, c.Direccion,
       sg.Nombre AS Segmento,
       ci.Nombre AS Ciudad, d.Nombre AS Departamento, r.Nombre AS Region, p.Nombre AS Pais,
       c.FechaRegistro, c.Activo
INTO stg.SQL_Clientes
FROM FINALBI_OLTP.dbo.Clientes c -- permite leer la base oltp del mismo servidor
JOIN FINALBI_OLTP.dbo.SegmentosCliente sg ON sg.SegmentoID = c.SegmentoID -- unimos tabls de oltp donde los datos estan separados en muchas tablas
JOIN FINALBI_OLTP.dbo.Ciudades ci         ON ci.CiudadID = c.CiudadID -- y en cdada una  solo hay un numero que apnta a otra tabla no el nombre
JOIN FINALBI_OLTP.dbo.Departamentos d     ON d.DepartamentoID = ci.DepartamentoID -- traemos el nombre para tabla dimensiones 
JOIN FINALBI_OLTP.dbo.Regiones r          ON r.RegionID = d.RegionID -- o tramos llaves o num para tablas de hechos 
JOIN FINALBI_OLTP.dbo.Paises p            ON p.PaisID = r.PaisID;  -- desnormalizacion t4

/* 2.2 Productos (con subcategoría, categoría, marca y proveedor) */
DROP TABLE IF EXISTS stg.SQL_Productos;
SELECT pr.ProductoID, pr.SKU, pr.Nombre,
       sc.Nombre AS Subcategoria, ca.Nombre AS Categoria,
       m.Nombre AS Marca, pv.RazonSocial AS Proveedor,
       pr.CostoUnitario, pr.PrecioLista, pr.Activo
INTO stg.SQL_Productos
FROM FINALBI_OLTP.dbo.Productos pr
JOIN FINALBI_OLTP.dbo.Subcategorias sc ON sc.SubcategoriaID = pr.SubcategoriaID
JOIN FINALBI_OLTP.dbo.Categorias ca    ON ca.CategoriaID = sc.CategoriaID
JOIN FINALBI_OLTP.dbo.Marcas m         ON m.MarcaID = pr.MarcaID
JOIN FINALBI_OLTP.dbo.Proveedores pv   ON pv.ProveedorID = pr.ProveedorID;

/* 2.3 Sucursales (con geografía) */
DROP TABLE IF EXISTS stg.SQL_Sucursales;
SELECT s.SucursalID, s.Nombre, s.TipoSucursal, s.FechaApertura,
       ci.Nombre AS Ciudad, d.Nombre AS Departamento, r.Nombre AS Region, p.Nombre AS Pais
INTO stg.SQL_Sucursales
FROM FINALBI_OLTP.dbo.Sucursales s
JOIN FINALBI_OLTP.dbo.Ciudades ci     ON ci.CiudadID = s.CiudadID  -- hace las copias pero aun  no las pasa a stg.Cliente_limpio
JOIN FINALBI_OLTP.dbo.Departamentos d ON d.DepartamentoID = ci.DepartamentoID -- esto se hará en 04_ETL_Dimensiones_y_Ventas.sql donde se pasa a las dimensiones finales
JOIN FINALBI_OLTP.dbo.Regiones r      ON r.RegionID = d.RegionID
JOIN FINALBI_OLTP.dbo.Paises p        ON p.PaisID = r.PaisID;

/* 2.4 Canales de venta */
DROP TABLE IF EXISTS stg.SQL_CanalesVenta;
SELECT CanalID, Nombre
INTO stg.SQL_CanalesVenta
FROM FINALBI_OLTP.dbo.CanalesVenta;

/* 2.5 Empleados (con cargo y sucursal) */
DROP TABLE IF EXISTS stg.SQL_Empleados;
SELECT e.EmpleadoID, e.NumeroDocumento, e.Nombres, e.Apellidos,
       cg.Nombre AS Cargo, s.Nombre AS Sucursal, e.FechaIngreso, e.Activo
INTO stg.SQL_Empleados
FROM FINALBI_OLTP.dbo.Empleados e
JOIN FINALBI_OLTP.dbo.Cargos cg    ON cg.CargoID = e.CargoID
JOIN FINALBI_OLTP.dbo.Sucursales s ON s.SucursalID = e.SucursalID;

/* 2.6 Ventas: TODAS las líneas, con el estado del pedido (T6 se aplica al cargar la fact) */
DROP TABLE IF EXISTS stg.SQL_Ventas;
SELECT d.DetalleID, p.PedidoID, p.NumeroPedido, p.FechaPedido, p.ClienteID, p.SucursalID,
       p.EmpleadoID, p.CanalID, e.Nombre AS Estado,
       d.ProductoID, d.Cantidad, d.PrecioUnitario, d.CostoUnitario, d.PorcentajeDescuento
INTO stg.SQL_Ventas
FROM FINALBI_OLTP.dbo.DetallePedido d
JOIN FINALBI_OLTP.dbo.Pedidos p        ON p.PedidoID = d.PedidoID
JOIN FINALBI_OLTP.dbo.EstadosPedido e  ON e.EstadoID = p.EstadoID;

/* 2.7 Pagos (con nombre del método de pago) */
DROP TABLE IF EXISTS stg.SQL_Pagos;
SELECT g.PagoID, g.PedidoID, p.NumeroPedido, m.Nombre AS MetodoPago,
       g.FechaPago, g.Valor, g.NumeroCuotas
INTO stg.SQL_Pagos
FROM FINALBI_OLTP.dbo.Pagos g
JOIN FINALBI_OLTP.dbo.Pedidos p      ON p.PedidoID = g.PedidoID
JOIN FINALBI_OLTP.dbo.MetodosPago m  ON m.MetodoPagoID = g.MetodoPagoID;
GO

/* Conteos de staging (captura) */
SELECT N'stg.SQL_Clientes' AS Tabla, COUNT(*) AS Registros FROM stg.SQL_Clientes
UNION ALL SELECT N'stg.SQL_Productos',   COUNT(*) FROM stg.SQL_Productos
UNION ALL SELECT N'stg.SQL_Sucursales',  COUNT(*) FROM stg.SQL_Sucursales
UNION ALL SELECT N'stg.SQL_CanalesVenta',COUNT(*) FROM stg.SQL_CanalesVenta
UNION ALL SELECT N'stg.SQL_Empleados',   COUNT(*) FROM stg.SQL_Empleados
UNION ALL SELECT N'stg.SQL_Ventas',      COUNT(*) FROM stg.SQL_Ventas
UNION ALL SELECT N'stg.SQL_Pagos',       COUNT(*) FROM stg.SQL_Pagos;
GO


/* =====================================================================
   Acá se hacen las transformaciones 
   T1, T2, T3 (Y T4) SOBRE CLIENTES -> stg.Cliente_Limpio
   T1: TRIM y CONCAT_WS (CONCAT_WS ignora NULL: las empresas quedan bien)
   T2: F -> Femenino, M -> Masculino, NULL -> No aplica
   T3: edad cumplida al 31-12-2025 y rango (empresas: No aplica)
   T4: ciudad, departamento, región y país ya vienen desnormalizados

   que hacemos? Toma los clientes crudos de stg.SQL_Clientes y crea una tabla limpia, stg.Cliente_Limpio.
   Esta tabla es la que usa quien arma DIM_Cliente (parte Mongo).
   ===================================================================== */
USE FINALBI_DW_GrupoN;
GO

DROP TABLE IF EXISTS stg.Cliente_Limpio;

DECLARE @Corte DATE = '2025-12-31';

SELECT c.ClienteID,
       c.TipoDocumento,
       c.NumeroDocumento,
       CASE WHEN c.TipoDocumento = 'NIT' THEN N'Empresa' ELSE N'Persona' END AS TipoCliente,
       CONCAT_WS(N' ', NULLIF(TRIM(c.Nombres), N''), NULLIF(TRIM(c.Apellidos), N'')) AS NombreCompleto, -- t1: armar nombre completo
       CASE c.Genero WHEN 'F' THEN N'Femenino'  -- t2: se apsa de f-> femenino y de m->masculino
                     WHEN 'M' THEN N'Masculino'
                     ELSE N'No aplica' END AS Genero,
       c.FechaNacimiento,
       CAST(a.Edad AS SMALLINT) AS Edad, -- t3: convierte edad a smaillint que tiene dim_cliente y le pone cases
       CASE WHEN a.Edad IS NULL THEN N'No aplica'
            WHEN a.Edad < 18    THEN N'Menor de 18'
            WHEN a.Edad <= 25   THEN N'18-25'
            WHEN a.Edad <= 35   THEN N'26-35'
            WHEN a.Edad <= 45   THEN N'36-45'
            WHEN a.Edad <= 60   THEN N'46-60'
            ELSE N'Más de 60' END AS RangoEdad,
       c.Segmento,
       c.FechaRegistro,
       c.Ciudad, c.Departamento, c.Region, c.Pais
INTO stg.Cliente_Limpio
FROM stg.SQL_Clientes c
CROSS APPLY (  -- calcular la edad 
    SELECT CASE WHEN c.FechaNacimiento IS NULL THEN NULL
                ELSE DATEDIFF(YEAR, c.FechaNacimiento, @Corte)
                     - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, c.FechaNacimiento, @Corte), c.FechaNacimiento) > @Corte
                            THEN 1 ELSE 0 END
           END AS Edad
) a;
GO

/* Comprobaciones de T1, T2 y T3 (captura) */
SELECT N'T1: nombres con espacios sobrantes (esperado 0)' AS Comprobacion, COUNT(*) AS Registros
FROM stg.Cliente_Limpio WHERE DATALENGTH(NombreCompleto) <> DATALENGTH(TRIM(NombreCompleto))
UNION ALL
SELECT N'T1: nombre completo vacío (esperado 0)', COUNT(*)
FROM stg.Cliente_Limpio WHERE DATALENGTH(TRIM(NombreCompleto)) = 0;

SELECT TipoCliente, Genero, COUNT(*) AS Clientes
FROM stg.Cliente_Limpio GROUP BY TipoCliente, Genero ORDER BY TipoCliente, Genero;

SELECT RangoEdad, COUNT(*) AS Clientes, MIN(Edad) AS EdadMin, MAX(Edad) AS EdadMax
FROM stg.Cliente_Limpio GROUP BY RangoEdad ORDER BY MIN(ISNULL(Edad, 999));
GO
