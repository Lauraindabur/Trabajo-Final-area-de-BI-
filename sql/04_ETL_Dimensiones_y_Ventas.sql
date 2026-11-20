/* =====================================================================
   04 · ETL DIMENSIONES Y FACT_Ventas (Persona 1)  [T5, T6, T7, T8]
   SECCIÓN 4  DIM_Producto (T5), DIM_Sucursal (T4), DIM_CanalVenta, DIM_Empleado
   SECCIÓN 5  DIM_Cliente base (parte SQL)
   SECCIÓN 6  FACT_Ventas (T6, T7, T8). CampanaAtribuidaKey queda en -1 (lo llena el 07).
   REQUISITOS: 02_Staging_SQL.sql y 03_ETL_Tiempo_T9.sql ejecutados.
   Re-ejecutable: la 4.0 vacia FACT_Ventas y las dimensiones (sin tocar la fila -1).
   ===================================================================== */

/* =====================================================================
   SECCIÓN 4 · DIMENSIONES: DIM_Producto (T5), DIM_Sucursal (T4),
                DIM_CanalVenta, DIM_Empleado
   4.0 Vaciar el destino: primero la fact (referencia a las dimensiones),
       luego las dimensiones sin tocar la fila -1, y reiniciar identity.
   ===================================================================== */
USE FINALBI_DW_GrupoN;
GO

TRUNCATE TABLE dbo.FACT_Ventas;

DELETE FROM dbo.DIM_Producto  WHERE ProductoKey  <> -1;
DELETE FROM dbo.DIM_Sucursal  WHERE SucursalKey  <> -1;
DELETE FROM dbo.DIM_CanalVenta WHERE CanalVentaKey <> -1;
DELETE FROM dbo.DIM_Empleado  WHERE EmpleadoKey  <> -1;

DBCC CHECKIDENT (N'dbo.DIM_Producto',   RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT (N'dbo.DIM_Sucursal',   RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT (N'dbo.DIM_CanalVenta', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT (N'dbo.DIM_Empleado',   RESEED, 0) WITH NO_INFOMSGS;
GO

/* 4.1 DIM_Producto (T5)
   RangoPrecio según PrecioLista. No se filtran los inactivos: tienen ventas. */
INSERT INTO dbo.DIM_Producto (ProductoID, SKU, NombreProducto, Subcategoria, Categoria, Marca, Proveedor,
                              CostoUnitario, PrecioLista, RangoPrecio)
SELECT p.ProductoID, p.SKU, TRIM(p.Nombre), p.Subcategoria, p.Categoria, p.Marca, p.Proveedor,
       p.CostoUnitario, p.PrecioLista,
       CASE WHEN p.PrecioLista < 50000  THEN N'Menos de $50.000'
            WHEN p.PrecioLista < 500000 THEN N'$50.000 a $499.999'
            ELSE N'$500.000 o más' END
FROM stg.SQL_Productos p
ORDER BY p.ProductoID;

/* 4.2 DIM_Sucursal (T4: ciudad -> departamento -> región -> país) */
INSERT INTO dbo.DIM_Sucursal (SucursalID, NombreSucursal, TipoSucursal, FechaApertura,
                              Ciudad, Departamento, Region, Pais)
SELECT s.SucursalID, TRIM(s.Nombre), s.TipoSucursal, s.FechaApertura,
       s.Ciudad, s.Departamento, s.Region, s.Pais
FROM stg.SQL_Sucursales s
ORDER BY s.SucursalID;

/* 4.3 DIM_CanalVenta */
INSERT INTO dbo.DIM_CanalVenta (CanalVentaID, NombreCanal)
SELECT c.CanalID, TRIM(c.Nombre)
FROM stg.SQL_CanalesVenta c
ORDER BY c.CanalID;

/* 4.4 DIM_Empleado (incluye jefes y cajeros aunque no vendan) */
INSERT INTO dbo.DIM_Empleado (EmpleadoID, NombreCompleto, Cargo)
SELECT e.EmpleadoID,
       CONCAT_WS(N' ', NULLIF(TRIM(e.Nombres), N''), NULLIF(TRIM(e.Apellidos), N'')),
       e.Cargo
FROM stg.SQL_Empleados e
ORDER BY e.EmpleadoID;
GO

/* Comprobaciones (captura) */
SELECT RangoPrecio, COUNT(*) AS Productos
FROM dbo.DIM_Producto WHERE ProductoKey <> -1 GROUP BY RangoPrecio ORDER BY MIN(PrecioLista);

SELECT N'DIM_Producto' AS Dimension, COUNT(*) AS Filas FROM dbo.DIM_Producto
UNION ALL SELECT N'DIM_Sucursal',   COUNT(*) FROM dbo.DIM_Sucursal
UNION ALL SELECT N'DIM_CanalVenta',  COUNT(*) FROM dbo.DIM_CanalVenta
UNION ALL SELECT N'DIM_Empleado',    COUNT(*) FROM dbo.DIM_Empleado;
GO


/* =====================================================================
   SECCIÓN 5 · DIM_Cliente (base)
   DIM_Tiempo (T9) ya la cargo 03_ETL_Tiempo_T9.sql; aqui NO se repite.
   ===================================================================== */
USE FINALBI_DW_GrupoN;
GO

/* 5.1 DIM_Cliente: parte SQL (desde stg.Cliente_Limpio) con valores por defecto en las
       columnas de Mongo. 05_ETL_Cliente_Mongo_T10_T14.sql las actualiza despues. */
IF NOT EXISTS (SELECT 1 FROM dbo.DIM_Cliente WHERE ClienteKey <> -1)
BEGIN
    INSERT INTO dbo.DIM_Cliente (ClienteID, TipoDocumento, NumeroDocumento, TipoCliente, NombreCompleto,
        Genero, FechaNacimiento, Edad, RangoEdad, Segmento, FechaRegistro, Ciudad, Departamento, Region, Pais,
        NivelFidelizacion, PuntosFidelizacion, CanalPreferido, OrigenRegistro, Intereses,
        AceptaEmail, AceptaSMS, AceptaWhatsApp, NPSPromedio, TipoNPS, TienePerfilMarketing)
    SELECT c.ClienteID, c.TipoDocumento, c.NumeroDocumento, c.TipoCliente, c.NombreCompleto,
           c.Genero, c.FechaNacimiento, c.Edad, c.RangoEdad, c.Segmento, c.FechaRegistro,
           c.Ciudad, c.Departamento, c.Region, c.Pais,
           N'Sin programa', 0, N'Sin perfil', N'Sin perfil', N'Sin perfil',
           0, 0, 0, NULL, N'Sin encuesta', 0
    FROM stg.Cliente_Limpio c
    ORDER BY c.ClienteID;

    PRINT N'DIM_Cliente: cargada con la parte SQL (Mongo se completa en el script 05).';
END
ELSE PRINT N'DIM_Cliente: ya tenía datos, no se modificó.';
GO


/* =====================================================================
   SECCIÓN 6 · FACT_Ventas (T6, T7, T8)
   Grano: una fila por línea de detalle de un pedido Completado.
   T6: solo pedidos en estado Completado.
   T7: método de pago principal = pago de mayor valor (desempate: PagoID).
   T8: pedido sin vendedor (web/app) -> EmpleadoKey = -1.
   Importes: TotalVenta usa la misma fórmula del OLTP;
             ValorDescuento = VentaBruta - TotalVenta (sin deriva de redondeo).
   Llave sin coincidencia en la dimensión -> -1 (la sección 7 lo reporta).
   CampanaAtribuidaKey queda en -1 (T19 lo actualiza después).
   ===================================================================== */
USE FINALBI_DW_GrupoN;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.DIM_Tiempo WHERE TiempoKey <> -1)
    THROW 50001, N'DIM_Tiempo está vacía: ejecute antes 03_ETL_Tiempo_T9.sql.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.DIM_Cliente WHERE ClienteKey <> -1)
    THROW 50002, N'DIM_Cliente está vacía: revise la sección 5.1.', 1;

TRUNCATE TABLE dbo.FACT_Ventas;

;WITH PagoPrincipal AS (
    SELECT g.PedidoID, g.MetodoPago,
           ROW_NUMBER() OVER (PARTITION BY g.PedidoID ORDER BY g.Valor DESC, g.PagoID) AS rn
    FROM stg.SQL_Pagos g
)
INSERT INTO dbo.FACT_Ventas (TiempoKey, ClienteKey, ProductoKey, SucursalKey, CanalVentaKey, EmpleadoKey,
                             NumeroPedido, DetalleID, MetodoPagoPrincipal,
                             Cantidad, PrecioUnit, PorcentajeDescuento, CostoUnit,
                             VentaBruta, ValorDescuento, TotalVenta, CostoTotal, Margen)
SELECT ISNULL(t.TiempoKey, -1),
       ISNULL(c.ClienteKey, -1),
       ISNULL(pr.ProductoKey, -1),
       ISNULL(su.SucursalKey, -1),
       ISNULL(cv.CanalVentaKey, -1),
       ISNULL(em.EmpleadoKey, -1),
       v.NumeroPedido,
       v.DetalleID,
       ISNULL(pp.MetodoPago, N'Desconocido'),
       v.Cantidad, v.PrecioUnitario, v.PorcentajeDescuento, v.CostoUnitario,
       m.VentaBruta,
       m.VentaBruta - m.TotalVenta,
       m.TotalVenta,
       m.CostoTotal,
       m.TotalVenta - m.CostoTotal
FROM stg.SQL_Ventas v
CROSS APPLY (
    SELECT CAST(v.Cantidad * v.PrecioUnitario AS DECIMAL(18,2)) AS VentaBruta,
           CAST(v.Cantidad * v.PrecioUnitario * (100 - v.PorcentajeDescuento) / 100 AS DECIMAL(18,2)) AS TotalVenta,
           CAST(v.Cantidad * v.CostoUnitario AS DECIMAL(18,2)) AS CostoTotal
) m
LEFT JOIN dbo.DIM_Tiempo     t  ON t.Fecha        = CAST(v.FechaPedido AS DATE)
LEFT JOIN dbo.DIM_Cliente    c  ON c.ClienteID    = v.ClienteID
LEFT JOIN dbo.DIM_Producto   pr ON pr.ProductoID  = v.ProductoID
LEFT JOIN dbo.DIM_Sucursal   su ON su.SucursalID  = v.SucursalID
LEFT JOIN dbo.DIM_CanalVenta cv ON cv.CanalVentaID = v.CanalID
LEFT JOIN dbo.DIM_Empleado   em ON em.EmpleadoID  = v.EmpleadoID
LEFT JOIN PagoPrincipal      pp ON pp.PedidoID    = v.PedidoID AND pp.rn = 1
WHERE v.Estado = N'Completado'
ORDER BY v.DetalleID;

SELECT COUNT(*) AS LineasCargadas,
       COUNT(DISTINCT NumeroPedido) AS PedidosCargados,
       SUM(TotalVenta) AS TotalVenta,
       SUM(Margen) AS Margen
FROM dbo.FACT_Ventas;
GO
