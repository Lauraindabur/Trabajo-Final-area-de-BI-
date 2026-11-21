/* =====================================================================
   BI · PARTE SQL SERVER (VENTAS) · 00 EXPLORACIÓN DEL OLTP

   CONTIENE
     SECCIÓN 0  Conteo de registros por tabla del OLTP (captura Parte 1, punto 1)
     SECCIÓN 1  Exploración de calidad (Parte 1, punto 3)

   REQUISITOS
     FINALBI_OLTP creada y poblada (scripts 01 y 02).
     Abrir el archivo como UTF-8 (tildes).

   SIGUIENTE PASO
     GrupoN_01_Staging.sql. Este archivo solo lee: se puede correr las veces que se quiera.
   ===================================================================== */


/* =====================================================================
   SECCIÓN 0 · CONTEO DE REGISTROS POR TABLA DEL OLTP
   Guardar captura (equivale a la tabla que muestra el script 02).
   ===================================================================== */
USE FINALBI_OLTP;
GO

SELECT t.name AS Tabla, SUM(p.rows) AS Registros /* usa las vistas del sistema para ver cuantas filas tiene cada una de las 19 tablas*/
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
GROUP BY t.name
ORDER BY t.name;
GO


/* =====================================================================
   SECCIÓN 1 · EXPLORACIÓN DE CALIDAD EN SQL SERVER
   1.1 Resumen: una fila por problema o verificación.
       Tipo = Dato sucio / Dato faltante / Inconsistencia  -> al reporte de calidad
       Tipo = Regla de negocio                              -> regla documentada
       Tipo = Verificación (esperado 0)                     -> evidencia de revisión
   NOTA: se usa DATALENGTH porque "=" y LEN ignoran los espacios finales.
   ===================================================================== */
USE FINALBI_OLTP;
GO

SELECT Tipo, Problema, Tabla, Registros  /* cada select revisa una cosa y devuelve una fila y se pega con union all */
FROM (
    /* ---- Clientes ---- */
    SELECT 1 AS Orden, N'Dato sucio' AS Tipo, N'Nombres con espacios sobrantes' AS Problema, N'Clientes' AS Tabla, COUNT(*) AS Registros
    FROM dbo.Clientes WHERE DATALENGTH(Nombres) <> DATALENGTH(TRIM(Nombres))
    UNION ALL
    SELECT 2, N'Verificación (esperado 0)', N'Apellidos con espacios sobrantes', N'Clientes', COUNT(*)
    FROM dbo.Clientes WHERE Apellidos IS NOT NULL AND DATALENGTH(Apellidos) <> DATALENGTH(TRIM(Apellidos))
    UNION ALL
    SELECT 3, N'Dato faltante', N'Clientes sin email (NULL)', N'Clientes', COUNT(*)
    FROM dbo.Clientes WHERE Email IS NULL
    UNION ALL
    SELECT 4, N'Verificación (esperado 0)', N'Email vacío (cadena en blanco)', N'Clientes', COUNT(*)
    FROM dbo.Clientes WHERE Email IS NOT NULL AND DATALENGTH(TRIM(Email)) = 0
    UNION ALL
    SELECT 5, N'Dato faltante', N'Clientes sin teléfono (NULL)', N'Clientes', COUNT(*)
    FROM dbo.Clientes WHERE Telefono IS NULL
    UNION ALL
    SELECT 6, N'Regla de negocio', N'Empresas (NIT) sin género ni fecha de nacimiento', N'Clientes', COUNT(*)
    FROM dbo.Clientes WHERE TipoDocumento = 'NIT' AND Genero IS NULL AND FechaNacimiento IS NULL
    UNION ALL
    SELECT 7, N'Verificación (esperado 0)', N'Personas sin género o sin fecha de nacimiento', N'Clientes', COUNT(*)
    FROM dbo.Clientes WHERE TipoDocumento <> 'NIT' AND (Genero IS NULL OR FechaNacimiento IS NULL)
    UNION ALL
    SELECT 8, N'Verificación (esperado 0)', N'Personas menores de 18 años al 31-12-2025', N'Clientes', COUNT(*)
    FROM dbo.Clientes WHERE FechaNacimiento > '2007-12-31'
    UNION ALL
    SELECT 9, N'Verificación (esperado 0)', N'Emails duplicados', N'Clientes', COUNT(*)
    FROM (SELECT Email FROM dbo.Clientes WHERE Email IS NOT NULL GROUP BY Email HAVING COUNT(*) > 1) x
    UNION ALL
    SELECT 10, N'Dato sucio', N'Clientes sin ningún pedido', N'Clientes', COUNT(*)
    FROM dbo.Clientes c WHERE NOT EXISTS (SELECT 1 FROM dbo.Pedidos p WHERE p.ClienteID = c.ClienteID)
    /* ---- Productos ---- */
    UNION ALL
    SELECT 11, N'Regla de negocio', N'Productos inactivos (Activo = 0)', N'Productos', COUNT(*)
    FROM dbo.Productos WHERE Activo = 0
    UNION ALL
    SELECT 12, N'Inconsistencia', N'Líneas vendidas de productos inactivos', N'DetallePedido', COUNT(*)
    FROM dbo.DetallePedido d JOIN dbo.Productos p ON p.ProductoID = d.ProductoID WHERE p.Activo = 0
    UNION ALL
    SELECT 13, N'Inconsistencia', N'Líneas vendidas a precio distinto del precio de lista (2024)', N'DetallePedido', COUNT(*)
    FROM dbo.DetallePedido d JOIN dbo.Productos p ON p.ProductoID = d.ProductoID WHERE d.PrecioUnitario <> p.PrecioLista
    /* ---- Pedidos ---- */
    UNION ALL
    SELECT 14, N'Regla de negocio', N'Pedidos Cancelado (no se cargan, T6)', N'Pedidos', COUNT(*)
    FROM dbo.Pedidos p JOIN dbo.EstadosPedido e ON e.EstadoID = p.EstadoID WHERE e.Nombre = N'Cancelado'
    UNION ALL
    SELECT 15, N'Regla de negocio', N'Pedidos Devuelto (no se cargan, T6)', N'Pedidos', COUNT(*)
    FROM dbo.Pedidos p JOIN dbo.EstadosPedido e ON e.EstadoID = p.EstadoID WHERE e.Nombre = N'Devuelto'
    UNION ALL
    SELECT 16, N'Regla de negocio', N'Pedidos sin empleado (EmpleadoID NULL, T8)', N'Pedidos', COUNT(*)
    FROM dbo.Pedidos WHERE EmpleadoID IS NULL
    UNION ALL
    SELECT 17, N'Verificación (esperado 0)', N'Pedidos sin empleado en Tienda física o Televentas', N'Pedidos', COUNT(*)
    FROM dbo.Pedidos p JOIN dbo.CanalesVenta c ON c.CanalID = p.CanalID
    WHERE p.EmpleadoID IS NULL AND c.Nombre IN (N'Tienda física', N'Televentas')
    UNION ALL
    SELECT 18, N'Verificación (esperado 0)', N'Pedidos con NumeroPedido NULL', N'Pedidos', COUNT(*)
    FROM dbo.Pedidos WHERE NumeroPedido IS NULL
    UNION ALL
    SELECT 19, N'Verificación (esperado 0)', N'Pedidos fuera del rango 2024-2025', N'Pedidos', COUNT(*)
    FROM dbo.Pedidos WHERE FechaPedido < '2024-01-01' OR FechaPedido >= '2026-01-01'
    UNION ALL
    SELECT 20, N'Verificación (esperado 0)', N'Pedidos sin líneas de detalle', N'Pedidos', COUNT(*)
    FROM dbo.Pedidos p WHERE NOT EXISTS (SELECT 1 FROM dbo.DetallePedido d WHERE d.PedidoID = p.PedidoID)
    UNION ALL
    SELECT 21, N'Verificación (esperado 0)', N'Canal y sucursal incoherentes', N'Pedidos', COUNT(*)
    FROM dbo.Pedidos p
    JOIN dbo.CanalesVenta c ON c.CanalID = p.CanalID
    JOIN dbo.Sucursales s ON s.SucursalID = p.SucursalID
    WHERE (c.Nombre = N'Tienda física' AND s.TipoSucursal <> N'Física')
       OR (c.Nombre <> N'Tienda física' AND s.TipoSucursal <> N'Virtual')
    UNION ALL
    SELECT 22, N'Verificación (esperado 0)', N'Empleado de una sucursal distinta a la del pedido', N'Pedidos', COUNT(*)
    FROM dbo.Pedidos p JOIN dbo.Empleados e ON e.EmpleadoID = p.EmpleadoID WHERE e.SucursalID <> p.SucursalID
    /* ---- Pagos ---- */
    UNION ALL
    SELECT 23, N'Verificación (esperado 0)', N'Pedidos Completado sin pago', N'Pagos', COUNT(*)
    FROM dbo.Pedidos p JOIN dbo.EstadosPedido e ON e.EstadoID = p.EstadoID
    WHERE e.Nombre = N'Completado' AND NOT EXISTS (SELECT 1 FROM dbo.Pagos g WHERE g.PedidoID = p.PedidoID)
    UNION ALL
    SELECT 24, N'Regla de negocio', N'Pedidos Cancelado sin pago', N'Pagos', COUNT(*)
    FROM dbo.Pedidos p JOIN dbo.EstadosPedido e ON e.EstadoID = p.EstadoID
    WHERE e.Nombre = N'Cancelado' AND NOT EXISTS (SELECT 1 FROM dbo.Pagos g WHERE g.PedidoID = p.PedidoID)
    UNION ALL
    SELECT 25, N'Regla de negocio', N'Pedidos Devuelto que conservan su pago', N'Pagos', COUNT(*)
    FROM dbo.Pedidos p JOIN dbo.EstadosPedido e ON e.EstadoID = p.EstadoID
    WHERE e.Nombre = N'Devuelto' AND EXISTS (SELECT 1 FROM dbo.Pagos g WHERE g.PedidoID = p.PedidoID)
    UNION ALL
    SELECT 26, N'Verificación (esperado 0)', N'Pedidos con más de un pago (afecta T7)', N'Pagos', COUNT(*)
    FROM (SELECT PedidoID FROM dbo.Pagos GROUP BY PedidoID HAVING COUNT(*) > 1) x
    UNION ALL
    SELECT 27, N'Verificación (esperado 0)', N'Pagos con valor distinto a la suma neta de sus líneas', N'Pagos', COUNT(*)
    FROM dbo.Pagos g
    CROSS APPLY (SELECT CAST(SUM(d.Cantidad * d.PrecioUnitario * (100 - d.PorcentajeDescuento) / 100) AS DECIMAL(14,2)) AS Total
                 FROM dbo.DetallePedido d WHERE d.PedidoID = g.PedidoID) t
    WHERE g.Valor <> t.Total
) q
ORDER BY Orden;
GO

/* 1.2 Muestras para el documento */ /* 4 consultas pequeñas que sirveen como evidencia que pide el punto 3 parte 1 */
-- Nombres con espacios sobrantes (los corchetes hacen visibles los espacios)
SELECT TOP (10) ClienteID, CONCAT(N'[', Nombres, N']') AS NombreEntreCorchetes,
       DATALENGTH(Nombres) AS BytesOriginal, DATALENGTH(TRIM(Nombres)) AS BytesLimpio
FROM dbo.Clientes
WHERE DATALENGTH(Nombres) <> DATALENGTH(TRIM(Nombres))
ORDER BY ClienteID;

-- Productos inactivos con más líneas vendidas -> productos inativos con mas ventas
SELECT TOP (10) p.ProductoID, p.SKU, p.Activo, COUNT(*) AS LineasVendidas
FROM dbo.DetallePedido d JOIN dbo.Productos p ON p.ProductoID = d.ProductoID
WHERE p.Activo = 0
GROUP BY p.ProductoID, p.SKU, p.Activo
ORDER BY LineasVendidas DESC;

-- Precio cobrado frente a precio de lista  -> muestra que en 2024 se vencio a pecio distinto al de la lsita 
SELECT TOP (10) d.DetalleID, p.ProductoID, YEAR(o.FechaPedido) AS Anio, p.PrecioLista, d.PrecioUnitario,
       CAST(d.PrecioUnitario * 1.0 / p.PrecioLista AS DECIMAL(6,3)) AS RazonPrecio
FROM dbo.DetallePedido d
JOIN dbo.Productos p ON p.ProductoID = d.ProductoID
JOIN dbo.Pedidos o ON o.PedidoID = d.PedidoID
WHERE d.PrecioUnitario <> p.PrecioLista
ORDER BY d.DetalleID;

-- Distribución de pedidos por estado y canal -> muestra cuantis pedidos se pirden por estado
SELECT e.Nombre AS Estado, c.Nombre AS Canal, COUNT(*) AS Pedidos
FROM dbo.Pedidos p
JOIN dbo.EstadosPedido e ON e.EstadoID = p.EstadoID
JOIN dbo.CanalesVenta c ON c.CanalID = p.CanalID
GROUP BY e.Nombre, c.Nombre
ORDER BY e.Nombre, c.Nombre;
GO
