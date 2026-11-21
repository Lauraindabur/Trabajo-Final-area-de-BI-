/* =====================================================================
   08 · VALIDACIÓN GENERAL (script unificado)   
   Revisa que lo que cargaron los otros scripts esté bien.
   SECCIÓN 7  Ventas: conteos, conciliación por estado, cuadre de dinero, miembro -1, T7
   SECCIÓN 8  Consolidado (OK/ERROR): extracción Mongo, marketing, clientes y perfiles,
              DIM_Tiempo (T9), geografía (T4), miembro -1 en FACT_InteraccionMarketing
              (Parte 4 punto 3), coherencia de banderas y T19.
   SECCIÓN 9  Reporte de calidad T10-T18 (cuántos registros afectó cada regla)
   SECCIÓN 10 Validación de perfiles de la Persona 2 (OK/ERROR propios)

   Al final: resumen con el total de controles OK y ERROR.
   
   ===================================================================== */
USE FINALBI_DW_GrupoN;
GO

/* =====================================================================
   SECCIÓN 7 · VALIDACIÓN DE LA CARGA DE VENTAS 
   comprobar que FACT_Ventas y sus dimensiones se cargaron completas y con los números correctos, comparándolas contra el OLTP
   Todas las columnas "Resultado" deben decir OK. 
   ===================================================================== */
USE FINALBI_DW_GrupoN;
GO

/* 7.1 Conteos origen -> destino en cada paso */
SELECT x.Paso, x.Origen, x.Destino,
       CASE WHEN x.Origen = x.Destino THEN N'OK' ELSE N'ERROR' END AS Resultado --si origen y destino son iguales, escribe OK; si no, ERROR
FROM (
    SELECT 1 AS Orden, N'OLTP.DetallePedido -> stg.SQL_Ventas' AS Paso,
           (SELECT COUNT(*) FROM FINALBI_OLTP.dbo.DetallePedido) AS Origen,
           (SELECT COUNT(*) FROM stg.SQL_Ventas) AS Destino
    UNION ALL SELECT 2, N'OLTP.Pagos -> stg.SQL_Pagos',
           (SELECT COUNT(*) FROM FINALBI_OLTP.dbo.Pagos), (SELECT COUNT(*) FROM stg.SQL_Pagos)
    UNION ALL SELECT 3, N'OLTP.Clientes -> stg.Cliente_Limpio',
           (SELECT COUNT(*) FROM FINALBI_OLTP.dbo.Clientes), (SELECT COUNT(*) FROM stg.Cliente_Limpio)
    UNION ALL SELECT 4, N'OLTP.Productos -> DIM_Producto (sin -1)',
           (SELECT COUNT(*) FROM FINALBI_OLTP.dbo.Productos),
           (SELECT COUNT(*) FROM dbo.DIM_Producto WHERE ProductoKey <> -1)
    UNION ALL SELECT 5, N'OLTP.Sucursales -> DIM_Sucursal (sin -1)',
           (SELECT COUNT(*) FROM FINALBI_OLTP.dbo.Sucursales),
           (SELECT COUNT(*) FROM dbo.DIM_Sucursal WHERE SucursalKey <> -1)
    UNION ALL SELECT 6, N'OLTP.CanalesVenta -> DIM_CanalVenta (sin -1)',
           (SELECT COUNT(*) FROM FINALBI_OLTP.dbo.CanalesVenta),
           (SELECT COUNT(*) FROM dbo.DIM_CanalVenta WHERE CanalVentaKey <> -1)
    UNION ALL SELECT 7, N'OLTP.Empleados -> DIM_Empleado (sin -1)',
           (SELECT COUNT(*) FROM FINALBI_OLTP.dbo.Empleados),
           (SELECT COUNT(*) FROM dbo.DIM_Empleado WHERE EmpleadoKey <> -1)
    UNION ALL SELECT 8, N'OLTP líneas de pedidos Completado -> FACT_Ventas',
           (SELECT COUNT(*) FROM FINALBI_OLTP.dbo.DetallePedido d
            JOIN FINALBI_OLTP.dbo.Pedidos p ON p.PedidoID = d.PedidoID
            JOIN FINALBI_OLTP.dbo.EstadosPedido e ON e.EstadoID = p.EstadoID
            WHERE e.Nombre = N'Completado'),
           (SELECT COUNT(*) FROM dbo.FACT_Ventas)
    UNION ALL SELECT 9, N'OLTP pedidos Completado -> pedidos distintos en FACT_Ventas',
           (SELECT COUNT(*) FROM FINALBI_OLTP.dbo.Pedidos p
            JOIN FINALBI_OLTP.dbo.EstadosPedido e ON e.EstadoID = p.EstadoID
            WHERE e.Nombre = N'Completado'),
           (SELECT COUNT(DISTINCT NumeroPedido) FROM dbo.FACT_Ventas)
) x
ORDER BY x.Orden;
GO

/* 7.2 Conciliación por estado: responde a ¿llegaron todas las filas en cada paso? */
SELECT o.Estado, o.Pedidos, o.Lineas AS LineasOrigen,
       CASE WHEN o.Estado = N'Completado' THEN (SELECT COUNT(*) FROM dbo.FACT_Ventas) ELSE 0 END AS LineasEnFact,
       CASE WHEN o.Estado = N'Completado' THEN o.Lineas - (SELECT COUNT(*) FROM dbo.FACT_Ventas)
            ELSE o.Lineas END AS LineasDescartadas,
       CASE WHEN o.Estado = N'Completado' THEN N'Ninguna'
            ELSE N'T6: solo se cargan pedidos Completado' END AS Motivo
FROM (
    SELECT e.Nombre AS Estado, COUNT(DISTINCT p.PedidoID) AS Pedidos, COUNT(*) AS Lineas
    FROM FINALBI_OLTP.dbo.DetallePedido d
    JOIN FINALBI_OLTP.dbo.Pedidos p       ON p.PedidoID = d.PedidoID
    JOIN FINALBI_OLTP.dbo.EstadosPedido e ON e.EstadoID = p.EstadoID
    GROUP BY e.Nombre
) o
ORDER BY o.Estado;
GO

/* 7.3 Cuadre de dinero: venta neta de pedidos Completado (OLTP) = SUM(TotalVenta) (DW) */
DECLARE @oltpVenta DECIMAL(18,2), @oltpCosto DECIMAL(18,2);
DECLARE @dwVenta DECIMAL(18,2), @dwCosto DECIMAL(18,2), @dwMargen DECIMAL(18,2);

SELECT @oltpVenta = SUM(CAST(d.Cantidad * d.PrecioUnitario * (100 - d.PorcentajeDescuento) / 100 AS DECIMAL(18,2))),
       @oltpCosto = SUM(CAST(d.Cantidad * d.CostoUnitario AS DECIMAL(18,2)))
FROM FINALBI_OLTP.dbo.DetallePedido d
JOIN FINALBI_OLTP.dbo.Pedidos p       ON p.PedidoID = d.PedidoID
JOIN FINALBI_OLTP.dbo.EstadosPedido e ON e.EstadoID = p.EstadoID
WHERE e.Nombre = N'Completado';

SELECT @dwVenta = SUM(TotalVenta), @dwCosto = SUM(CostoTotal), @dwMargen = SUM(Margen)
FROM dbo.FACT_Ventas;

SELECT c.Concepto, c.Origen_OLTP, c.Destino_DW, c.Destino_DW - c.Origen_OLTP AS Diferencia,
       CASE WHEN c.Destino_DW = c.Origen_OLTP THEN N'OK' ELSE N'ERROR' END AS Resultado
FROM (
    SELECT N'Venta neta (TotalVenta)' AS Concepto, ISNULL(@oltpVenta, 0) AS Origen_OLTP, ISNULL(@dwVenta, 0) AS Destino_DW
    UNION ALL SELECT N'Costo total', ISNULL(@oltpCosto, 0), ISNULL(@dwCosto, 0)
    UNION ALL SELECT N'Margen (venta neta - costo)', ISNULL(@oltpVenta, 0) - ISNULL(@oltpCosto, 0), ISNULL(@dwMargen, 0)
) c;
GO

/* 7.4 Cuadre de dinero mes a mes */
;WITH o AS (
    SELECT YEAR(p.FechaPedido) AS Anio, MONTH(p.FechaPedido) AS Mes,
           SUM(CAST(d.Cantidad * d.PrecioUnitario * (100 - d.PorcentajeDescuento) / 100 AS DECIMAL(18,2))) AS Venta
    FROM FINALBI_OLTP.dbo.DetallePedido d
    JOIN FINALBI_OLTP.dbo.Pedidos p       ON p.PedidoID = d.PedidoID
    JOIN FINALBI_OLTP.dbo.EstadosPedido e ON e.EstadoID = p.EstadoID
    WHERE e.Nombre = N'Completado'
    GROUP BY YEAR(p.FechaPedido), MONTH(p.FechaPedido)
),
w AS (
    SELECT t.Anio, t.Mes, SUM(f.TotalVenta) AS Venta
    FROM dbo.FACT_Ventas f
    JOIN dbo.DIM_Tiempo t ON t.TiempoKey = f.TiempoKey
    GROUP BY t.Anio, t.Mes
)
SELECT COALESCE(o.Anio, w.Anio) AS Anio, COALESCE(o.Mes, w.Mes) AS Mes,
       o.Venta AS VentaOLTP, w.Venta AS VentaDW,
       ISNULL(w.Venta, 0) - ISNULL(o.Venta, 0) AS Diferencia,
       CASE WHEN ISNULL(w.Venta, 0) = ISNULL(o.Venta, 0) THEN N'OK' ELSE N'ERROR' END AS Resultado
FROM o FULL OUTER JOIN w ON w.Anio = o.Anio AND w.Mes = o.Mes
ORDER BY Anio, Mes;
GO

/* 7.5 Uso del miembro -1 en FACT_Ventas, con su explicación */
SELECT u.Dimension, u.FilasConMiembro_1, u.Esperado, u.Explicacion,
       CASE WHEN u.FilasConMiembro_1 = u.Esperado THEN N'OK' ELSE N'ERROR' END AS Resultado
FROM (
    SELECT N'TiempoKey' AS Dimension, COUNT(*) AS FilasConMiembro_1, 0 AS Esperado,
           N'Toda fecha de pedido (2024-2025) existe en DIM_Tiempo' AS Explicacion
    FROM dbo.FACT_Ventas WHERE TiempoKey = -1
    UNION ALL SELECT N'ClienteKey', COUNT(*), 0, N'Todo ClienteID del OLTP existe en DIM_Cliente (hay llave foránea en el origen)'
    FROM dbo.FACT_Ventas WHERE ClienteKey = -1
    UNION ALL SELECT N'ProductoKey', COUNT(*), 0, N'Todo ProductoID existe en DIM_Producto (incluye inactivos)'
    FROM dbo.FACT_Ventas WHERE ProductoKey = -1
    UNION ALL SELECT N'SucursalKey', COUNT(*), 0, N'Toda sucursal existe en DIM_Sucursal'
    FROM dbo.FACT_Ventas WHERE SucursalKey = -1
    UNION ALL SELECT N'CanalVentaKey', COUNT(*), 0, N'Todo canal existe en DIM_CanalVenta'
    FROM dbo.FACT_Ventas WHERE CanalVentaKey = -1
    UNION ALL SELECT N'EmpleadoKey', COUNT(*),
           (SELECT COUNT(*) FROM stg.SQL_Ventas WHERE Estado = N'Completado' AND EmpleadoID IS NULL),
           N'T8: ventas web y app sin vendedor (EmpleadoID NULL en el origen)'
    FROM dbo.FACT_Ventas WHERE EmpleadoKey = -1
    UNION ALL SELECT N'MetodoPagoPrincipal = Desconocido', COUNT(*), 0, N'Todo pedido Completado tiene pago'
    FROM dbo.FACT_Ventas WHERE MetodoPagoPrincipal = N'Desconocido'
) u;

/* EmpleadoKey = -1 por canal: debe ser todo en Tienda online y App móvil, y cero en los demás */
SELECT cv.NombreCanal, COUNT(*) AS Lineas,
       SUM(CASE WHEN f.EmpleadoKey = -1 THEN 1 ELSE 0 END) AS LineasSinVendedor,
       CASE WHEN cv.NombreCanal IN (N'Tienda online', N'App móvil')
                 AND SUM(CASE WHEN f.EmpleadoKey = -1 THEN 1 ELSE 0 END) = COUNT(*) THEN N'OK'
            WHEN cv.NombreCanal NOT IN (N'Tienda online', N'App móvil')
                 AND SUM(CASE WHEN f.EmpleadoKey = -1 THEN 1 ELSE 0 END) = 0 THEN N'OK'
            ELSE N'ERROR' END AS Resultado
FROM dbo.FACT_Ventas f
JOIN dbo.DIM_CanalVenta cv ON cv.CanalVentaKey = f.CanalVentaKey
GROUP BY cv.NombreCanal
ORDER BY cv.NombreCanal;
GO

/* 7.6 Controles de T7: un método por pedido, el del pago de mayor valor,
       y pago igual al total de las líneas del pedido */
SELECT c.Control, c.Registros, CASE WHEN c.Registros = 0 THEN N'OK' ELSE N'ERROR' END AS Resultado
FROM (
    SELECT N'Pedidos con más de un método principal (esperado 0)' AS Control, COUNT(*) AS Registros
    FROM (SELECT NumeroPedido FROM dbo.FACT_Ventas
          GROUP BY NumeroPedido HAVING COUNT(DISTINCT MetodoPagoPrincipal) > 1) x
    UNION ALL
    SELECT N'Pedidos cuyo método no es el del pago de mayor valor (esperado 0)', COUNT(*)
    FROM (SELECT DISTINCT NumeroPedido, MetodoPagoPrincipal FROM dbo.FACT_Ventas) f
    JOIN stg.SQL_Pagos g ON g.NumeroPedido = f.NumeroPedido
    WHERE g.Valor = (SELECT MAX(g2.Valor) FROM stg.SQL_Pagos g2 WHERE g2.PedidoID = g.PedidoID)
      AND g.MetodoPago <> f.MetodoPagoPrincipal
    UNION ALL
    SELECT N'Pedidos cuyo pago no coincide con la suma de TotalVenta (esperado 0)', COUNT(*)
    FROM (SELECT NumeroPedido, SUM(TotalVenta) AS Total FROM dbo.FACT_Ventas GROUP BY NumeroPedido) x
    JOIN stg.SQL_Pagos g ON g.NumeroPedido = x.NumeroPedido
    WHERE g.Valor <> x.Total
) c;
GO


/* =====================================================================
   SECCIÓN 8 · CONTROLES CONSOLIDADOS (OK / ERROR)
   ===================================================================== */
USE FINALBI_DW_GrupoN;
GO
SET NOCOUNT ON;

DROP TABLE IF EXISTS stg.validacion_resultado;
CREATE TABLE stg.validacion_resultado (
    Orden INT IDENTITY(1,1), Seccion NVARCHAR(60), Control NVARCHAR(200),
    Esperado BIGINT, Obtenido BIGINT, Resultado AS (CASE WHEN Esperado = Obtenido THEN N'OK' ELSE N'ERROR' END));

/* 8.1 Extracción: documentos en Mongo = filas en staging */
INSERT INTO stg.validacion_resultado (Seccion, Control, Esperado, Obtenido)
SELECT N'8.1 Extracción Mongo', N'Mongo -> staging: ' + Coleccion, DocumentosOrigen, FilasCargadasStg
FROM stg.ControlExtraccion;

/* 8.2 Marketing y clientes: staging -> DW */
INSERT INTO stg.validacion_resultado (Seccion, Control, Esperado, Obtenido) VALUES
 (N'8.2 Staging -> DW', N'stg.mongo_campanas -> DIM_Campana (sin -1)',
    (SELECT COUNT(*) FROM stg.mongo_campanas), (SELECT COUNT(*) FROM dbo.DIM_Campana WHERE CampanaKey <> -1)),
 (N'8.2 Staging -> DW', N'stg.mongo_interacciones -> FACT_InteraccionMarketing',
    (SELECT COUNT(*) FROM stg.mongo_interacciones), (SELECT COUNT(*) FROM dbo.FACT_InteraccionMarketing)),
 (N'8.2 Staging -> DW', N'InteraccionID repetidos en la fact (esperado 0)',
    0, (SELECT COUNT(*) - COUNT(DISTINCT InteraccionID) FROM dbo.FACT_InteraccionMarketing)),
 (N'8.2 Staging -> DW', N'Interacciones con cupón redimido (campo cuponRedimido = true)',
    (SELECT COUNT(*) FROM stg.mongo_interacciones WHERE LOWER(TRIM(CuponRedimido)) = N'true'),
    (SELECT COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE CuponRedimido = 1)),
 (N'8.2 Staging -> DW', N'Interacciones con evento clic',
    (SELECT COUNT(DISTINCT InteraccionID) FROM stg.Interaccion_Evento WHERE TipoEvento = N'clic'),
    (SELECT COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE Clic = 1)),
 (N'8.2 Staging -> DW', N'OLTP.Clientes -> DIM_Cliente (sin -1)',
    (SELECT COUNT(*) FROM FINALBI_OLTP.dbo.Clientes), (SELECT COUNT(*) FROM dbo.DIM_Cliente WHERE ClienteKey <> -1)),
 (N'8.2 Staging -> DW', N'Clientes con perfil de marketing: stg.PerfilCliente -> DIM_Cliente',
    (SELECT COUNT(*) FROM stg.PerfilCliente p WHERE EXISTS (SELECT 1 FROM dbo.DIM_Cliente c WHERE c.ClienteID = p.ClienteID AND c.ClienteKey <> -1)),
    (SELECT COUNT(*) FROM dbo.DIM_Cliente WHERE TienePerfilMarketing = 1 AND ClienteKey <> -1)),
 (N'8.2 Staging -> DW', N'Perfiles sin cliente en el OLTP (esperado 0)',
    0, (SELECT COUNT(*) FROM stg.PerfilCliente p WHERE NOT EXISTS (SELECT 1 FROM dbo.DIM_Cliente c WHERE c.ClienteID = p.ClienteID AND c.ClienteKey <> -1)));

/* 8.3 DIM_Tiempo (T9): años completos, sin huecos, clave yyyymmdd */
INSERT INTO stg.validacion_resultado (Seccion, Control, Esperado, Obtenido)
SELECT N'8.3 DIM_Tiempo (T9)', x.Control, x.Esperado, x.Obtenido
FROM (
    SELECT N'Días cargados = días del calendario (sin huecos)' AS Control,
           DATEDIFF(DAY, MIN(Fecha), MAX(Fecha)) + 1 AS Esperado, COUNT(*) AS Obtenido
    FROM dbo.DIM_Tiempo WHERE TiempoKey <> -1
    UNION ALL SELECT N'Empieza un 1 de enero y termina un 31 de diciembre', 1,
           CASE WHEN MIN(Fecha) = DATEFROMPARTS(YEAR(MIN(Fecha)), 1, 1)
                 AND MAX(Fecha) = DATEFROMPARTS(YEAR(MAX(Fecha)), 12, 31) THEN 1 ELSE 0 END
    FROM dbo.DIM_Tiempo WHERE TiempoKey <> -1
    UNION ALL SELECT N'TiempoKey distinto de yyyymmdd (esperado 0)', 0, COUNT(*)
    FROM dbo.DIM_Tiempo WHERE TiempoKey <> -1 AND TiempoKey <> YEAR(Fecha) * 10000 + MONTH(Fecha) * 100 + DAY(Fecha)
    UNION ALL SELECT N'Nombres de mes/día vacíos (esperado 0)', 0, COUNT(*)
    FROM dbo.DIM_Tiempo WHERE TiempoKey <> -1 AND (NombreMes IS NULL OR NombreDia IS NULL OR NombreMes = N'' OR NombreDia = N'')
    UNION ALL SELECT N'Fines de semana mal marcados (esperado 0)', 0, COUNT(*)
    FROM dbo.DIM_Tiempo WHERE TiempoKey <> -1 AND EsFinDeSemana <> CASE WHEN NombreDia IN (N'Sábado', N'Domingo') THEN 1 ELSE 0 END
    UNION ALL SELECT N'Fila -1 presente', 1, COUNT(*) FROM dbo.DIM_Tiempo WHERE TiempoKey = -1
) x;

/* 8.4 Geografía (T4): ciudad -> departamento -> región -> país completos y consistentes */
INSERT INTO stg.validacion_resultado (Seccion, Control, Esperado, Obtenido) VALUES
 (N'8.4 Geografía (T4)', N'DIM_Cliente con geografía vacía (esperado 0)', 0,
    (SELECT COUNT(*) FROM dbo.DIM_Cliente WHERE ClienteKey <> -1
       AND (NULLIF(TRIM(Ciudad), N'') IS NULL OR NULLIF(TRIM(Departamento), N'') IS NULL
         OR NULLIF(TRIM(Region), N'') IS NULL OR NULLIF(TRIM(Pais), N'') IS NULL))),
 (N'8.4 Geografía (T4)', N'DIM_Sucursal con geografía vacía (esperado 0)', 0,
    (SELECT COUNT(*) FROM dbo.DIM_Sucursal WHERE SucursalKey <> -1
       AND (NULLIF(TRIM(Ciudad), N'') IS NULL OR NULLIF(TRIM(Departamento), N'') IS NULL
         OR NULLIF(TRIM(Region), N'') IS NULL OR NULLIF(TRIM(Pais), N'') IS NULL))),
 (N'8.4 Geografía (T4)', N'Ciudades con más de un departamento en DIM_Cliente (esperado 0)', 0,
    (SELECT COUNT(*) FROM (SELECT Ciudad FROM dbo.DIM_Cliente WHERE ClienteKey <> -1
                           GROUP BY Ciudad HAVING COUNT(DISTINCT Departamento) > 1) z));

/* 8.5 Parte 4 punto 3 (marketing): uso del miembro -1 en FACT_InteraccionMarketing
       (el de FACT_Ventas está en 7.5). Esperado de ClienteKey = interacciones cuyo clienteId no existe en el OLTP. */
INSERT INTO stg.validacion_resultado (Seccion, Control, Esperado, Obtenido) VALUES
 (N'8.5 Miembro -1 (marketing)', N'TiempoKey = -1 (todas las fechas caen en el calendario)', 0,
    (SELECT COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE TiempoKey = -1)),
 (N'8.5 Miembro -1 (marketing)', N'ClienteKey = -1 (T17: clienteId inexistente en el OLTP)',
    (SELECT COUNT(*) FROM stg.mongo_interacciones i
      WHERE NOT EXISTS (SELECT 1 FROM stg.SQL_Clientes c WHERE c.ClienteID = TRY_CAST(TRIM(i.ClienteID) AS INT))),
    (SELECT COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE ClienteKey = -1)),
 (N'8.5 Miembro -1 (marketing)', N'CampanaKey = -1 (toda campaña existe en DIM_Campana)', 0,
    (SELECT COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE CampanaKey = -1)),
 (N'8.5 Miembro -1 (marketing)', N'CanalMarketingKey = -1 (los 4 canales existen)', 0,
    (SELECT COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE CanalMarketingKey = -1));

/* 8.6 Coherencia de las banderas (propiedades de los datos de Mongo) */
INSERT INTO stg.validacion_resultado (Seccion, Control, Esperado, Obtenido) VALUES
 (N'8.6 Banderas', N'Entregado sin Enviado (esperado 0)', 0,
    (SELECT COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE Entregado = 1 AND Enviado = 0)),
 (N'8.6 Banderas', N'Abierto sin Entregado (esperado 0)', 0,
    (SELECT COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE Abierto = 1 AND Entregado = 0)),
 (N'8.6 Banderas', N'Cupón redimido sin clic (esperado 0)', 0,
    (SELECT COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE CuponRedimido = 1 AND Clic = 0)),
 (N'8.6 Banderas', N'HorasHastaApertura negativas (esperado 0)', 0,
    (SELECT COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE HorasHastaApertura < 0)),
 (N'8.6 Banderas', N'HorasHastaApertura con interacción sin apertura (esperado 0)', 0,
    (SELECT COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE HorasHastaApertura IS NOT NULL AND Abierto = 0));

/* 8.7 T19: coherencia de la atribución */
INSERT INTO stg.validacion_resultado (Seccion, Control, Esperado, Obtenido) VALUES
 (N'8.7 Atribución (T19)', N'Pedidos con más de una campaña atribuida (esperado 0)', 0,
    (SELECT COUNT(*) FROM (SELECT NumeroPedido FROM dbo.FACT_Ventas WHERE CampanaAtribuidaKey <> -1
                           GROUP BY NumeroPedido HAVING COUNT(DISTINCT CampanaAtribuidaKey) > 1) z)),
 (N'8.7 Atribución (T19)', N'Pedidos atribuidos de un cliente desconocido (esperado 0)', 0,
    (SELECT COUNT(*) FROM dbo.FACT_Ventas WHERE CampanaAtribuidaKey <> -1 AND ClienteKey = -1)),
 (N'8.7 Atribución (T19)', N'Pedidos atribuidos SIN clic de esa campaña en los 7 días previos (esperado 0)', 0,
    (SELECT COUNT(*) FROM (
        SELECT DISTINCT v.NumeroPedido, v.CampanaAtribuidaKey, v.ClienteKey, t.Fecha
        FROM dbo.FACT_Ventas v JOIN dbo.DIM_Tiempo t ON t.TiempoKey = v.TiempoKey
        WHERE v.CampanaAtribuidaKey <> -1) p
     WHERE NOT EXISTS (SELECT 1 FROM stg.Atribucion_Clics c
                       WHERE c.ClienteKey = p.ClienteKey AND c.CampanaKey = p.CampanaAtribuidaKey
                         AND p.Fecha BETWEEN c.FechaClic AND DATEADD(DAY, 7, c.FechaClic)))),
 (N'8.7 Atribución (T19)', N'Pedidos con clic válido en la ventana que quedaron sin atribuir (esperado 0)', 0,
    (SELECT COUNT(*) FROM (
        SELECT DISTINCT v.NumeroPedido, v.ClienteKey, t.Fecha
        FROM dbo.FACT_Ventas v JOIN dbo.DIM_Tiempo t ON t.TiempoKey = v.TiempoKey
        WHERE v.CampanaAtribuidaKey = -1 AND v.ClienteKey <> -1) p
     WHERE EXISTS (SELECT 1 FROM stg.Atribucion_Clics c
                   WHERE c.ClienteKey = p.ClienteKey AND p.Fecha BETWEEN c.FechaClic AND DATEADD(DAY, 7, c.FechaClic))));

SELECT Orden, Seccion, Control, Esperado, Obtenido, Resultado FROM stg.validacion_resultado ORDER BY Orden;
GO

/* =====================================================================
   SECCIÓN 9 · REPORTE DE CALIDAD T10-T18 (cuántos registros afectó cada regla)
   "Referencia" = valor calculado sobre los JSON entregados (iguales para todos los grupos).
   COINCIDE = igual a la referencia; REVISAR = distinto (confirmar que se cargaron los mismos JSON).
   ===================================================================== */
SELECT q.Regla, q.RegistrosAfectados, q.Referencia, q.Accion,
       CASE WHEN q.Referencia IS NULL THEN N'-' WHEN q.RegistrosAfectados = q.Referencia THEN N'COINCIDE' ELSE N'REVISAR' END AS Resultado
FROM (
    SELECT 1 AS Orden, N'T10 · perfiles con clienteId en texto' AS Regla,
           (SELECT COUNT(*) FROM stg.PerfilesMarketing WHERE ClienteIdTipoOrigen = N'string') AS RegistrosAfectados, 56 AS Referencia,
           N'TRIM + TRY_CAST a entero' AS Accion
    UNION ALL SELECT 2, N'T11 · perfiles descartados por duplicado (se deja el más reciente)',
           (SELECT COUNT(*) FROM stg.PerfilesMarketing) - (SELECT COUNT(*) FROM stg.PerfilCliente), 105,
           N'ROW_NUMBER por cliente, fechaActualizacion DESC'
    UNION ALL SELECT 3, N'T11 · clientes con perfil vigente', (SELECT COUNT(*) FROM stg.PerfilCliente), 5101, N'Un perfil por cliente'
    UNION ALL SELECT 4, N'T12 · clientes con intereses normalizados a las 6 categorías',
           (SELECT COUNT(*) FROM stg.PerfilCliente WHERE Intereses <> N'Sin intereses'), 5101, N'Sin tildes, mayúsculas ni espacios; Deporte pasa a Deportes'
    UNION ALL SELECT 5, N'T13 · clientes con perfil y sin programa de fidelización',
           (SELECT COUNT(*) FROM stg.PerfilCliente WHERE NivelFidelizacion = N'Sin programa'), 1533, N'Sin programa y 0 puntos'
    UNION ALL SELECT 6, N'T14 · TipoNPS = Promotor',   (SELECT COUNT(*) FROM stg.PerfilCliente WHERE TipoNPS = N'Promotor'), 1263, N'Promedio >= 9'
    UNION ALL SELECT 7, N'T14 · TipoNPS = Pasivo',     (SELECT COUNT(*) FROM stg.PerfilCliente WHERE TipoNPS = N'Pasivo'), 1417, N'Promedio >= 7 y < 9'
    UNION ALL SELECT 8, N'T14 · TipoNPS = Detractor',  (SELECT COUNT(*) FROM stg.PerfilCliente WHERE TipoNPS = N'Detractor'), 744, N'Promedio < 7'
    UNION ALL SELECT 9, N'T14 · TipoNPS = Sin encuesta', (SELECT COUNT(*) FROM stg.PerfilCliente WHERE TipoNPS = N'Sin encuesta'), 1677, N'NPSPromedio NULL'
    UNION ALL SELECT 10, N'T16 · eventos con fecha en texto dd/mm/aaaa hh:mm',
           (SELECT COUNT(*) FROM stg.Interaccion_Evento WHERE FechaOriginal LIKE N'[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]%'), 717,
           N'CONVERT estilo 103; UTC a UTC-5'
    UNION ALL SELECT 11, N'T16 · eventos cuya fecha no se pudo interpretar (esperado 0)',
           (SELECT COUNT(*) FROM stg.Interaccion_Evento WHERE FechaColombia IS NULL), 0, N'Se perderían del cálculo de fechas'
    UNION ALL SELECT 12, N'T17 · interacciones con clienteId inexistente, ClienteKey = -1',
           (SELECT COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE ClienteKey = -1), 212, N'Se conserva la interacción con el miembro desconocido'
    UNION ALL SELECT 13, N'T18 · presupuesto de campaña en texto',
           (SELECT COUNT(*) FROM stg.mongo_campanas WHERE TRY_CAST(Presupuesto AS DECIMAL(18,2)) IS NULL AND Presupuesto IS NOT NULL), 2,
           N'Se quitan los puntos de miles y se convierte a DECIMAL(18,2)'
    UNION ALL SELECT 14, N'T18 · campañas sin responsable',
           (SELECT COUNT(*) FROM stg.mongo_campanas WHERE Responsable IS NULL OR TRIM(Responsable) = N''), 1, N'Se asigna Sin asignar'
    UNION ALL SELECT 15, N'T15 · interacciones con cupón redimido',
           (SELECT COUNT(*) FROM dbo.FACT_InteraccionMarketing WHERE CuponRedimido = 1), 1359, N'Campo cuponRedimido del documento'
    UNION ALL SELECT 16, N'Total de interacciones cargadas', (SELECT COUNT(*) FROM dbo.FACT_InteraccionMarketing), 36106, N'-'
    UNION ALL SELECT 17, N'Total de campañas cargadas', (SELECT COUNT(*) FROM dbo.DIM_Campana WHERE CampanaKey <> -1), 24, N'-'
) q
ORDER BY q.Orden;

/* Nota para el dashboard: el canal redes_sociales solo registra impresion (nunca enviado, entregado ni abierto);
   las tasas de entrega y apertura deben calcularse sobre Email, SMS y WhatsApp. */
SELECT cm.NombreCanal, COUNT(*) AS Interacciones, SUM(f.Enviado) AS Enviados, SUM(f.Entregado) AS Entregados,
       SUM(f.Abierto) AS Abiertos, SUM(f.Impresion) AS Impresiones, SUM(f.Clic) AS Clics, SUM(f.CuponRedimido) AS Cupones
FROM dbo.FACT_InteraccionMarketing f
JOIN dbo.DIM_CanalMarketing cm ON cm.CanalMarketingKey = f.CanalMarketingKey
GROUP BY cm.NombreCanal ORDER BY cm.NombreCanal;
GO

/* =====================================================================
   SECCIÓN 10 · VALIDACIÓN DE PERFILES (Persona 2)
   ===================================================================== */
USE FINALBI_DW_GrupoN;
GO
SET NOCOUNT ON;

DECLARE @mongo INT = (SELECT DocumentosOrigen FROM stg.ControlExtraccion WHERE Coleccion = N'perfiles_marketing');
DECLARE @stg   INT = (SELECT COUNT(*) FROM stg.PerfilesMarketing);
DECLARE @limpio INT = (SELECT COUNT(*) FROM stg.PerfilCliente);
DECLARE @dim   INT = (SELECT COUNT(*) FROM dbo.DIM_Cliente WHERE TienePerfilMarketing = 1);
DECLARE @dup   INT = (SELECT RegistrosAfectados FROM dbo.ReporteCalidadDatos
                      WHERE Fuente = N'Mongo · perfiles' AND Transformacion = N'T11');
DECLARE @noNum INT = (SELECT RegistrosAfectados FROM dbo.ReporteCalidadDatos
                      WHERE Fuente = N'Mongo · perfiles' AND Problema LIKE N'clienteId que no se pudo%');
DECLARE @noOltp INT = (SELECT RegistrosAfectados FROM dbo.ReporteCalidadDatos
                      WHERE Fuente = N'Mongo · perfiles' AND Transformacion = N'INT');

/* 1. Conteos paso a paso */
SELECT Paso, Registros, Explicacion FROM (VALUES
    (1, N'MongoDB perfiles_marketing (documentos)', @mongo,  N'countDocuments() al momento de extraer'),
    (2, N'stg.PerfilesMarketing (filas crudas)',    @stg,    N'Debe ser igual a MongoDB'),
    (3, N'stg.PerfilCliente (1 por cliente)',       @limpio, CONCAT(N'stg - ', @dup, N' duplicados (T11) - ', @noNum, N' clienteId no numérico (T10)')),
    (4, N'DIM_Cliente con perfil de mercadeo',      @dim,    CONCAT(N'stg.PerfilCliente - ', @noOltp, N' clientes que no existen en el OLTP')),
    (5, N'DIM_Cliente sin perfil de mercadeo',
        (SELECT COUNT(*) FROM dbo.DIM_Cliente WHERE TienePerfilMarketing = 0 AND ClienteKey <> -1),
        N'Clientes del OLTP que no tienen perfil en MongoDB: valores por defecto')
) v(Orden, Paso, Registros, Explicacion)
ORDER BY Orden;

/* 2. Cuadre: ningún registro se pierde sin explicación */
SELECT N'MongoDB = stg' AS Control,
       CASE WHEN @mongo = @stg THEN N'OK' ELSE N'ERROR' END AS Resultado
UNION ALL
SELECT N'stg - duplicados - no numéricos = perfil limpio',
       CASE WHEN @stg - @dup - @noNum = @limpio THEN N'OK' ELSE N'ERROR' END
UNION ALL
SELECT N'perfil limpio - no existen en OLTP = DIM_Cliente con perfil',
       CASE WHEN @limpio - @noOltp = @dim THEN N'OK' ELSE N'ERROR' END
UNION ALL
SELECT N'Intereses solo con las 6 categorías oficiales',
       CASE WHEN NOT EXISTS (
            SELECT 1 FROM dbo.DIM_Cliente d
            CROSS APPLY STRING_SPLIT(d.Intereses, N',') s
            WHERE d.TienePerfilMarketing = 1
              AND LTRIM(s.value) NOT IN (SELECT Nombre FROM FINALBI_OLTP.dbo.Categorias))
            THEN N'OK' ELSE N'ERROR' END;

/* 3. Distribución de las columnas de mercadeo en DIM_Cliente */
SELECT NivelFidelizacion, COUNT(*) AS Clientes, AVG(PuntosFidelizacion) AS PuntosPromedio
FROM dbo.DIM_Cliente WHERE ClienteKey <> -1
GROUP BY NivelFidelizacion ORDER BY Clientes DESC;

SELECT TipoNPS, COUNT(*) AS Clientes, CAST(AVG(NPSPromedio) AS DECIMAL(4,2)) AS NPSPromedio
FROM dbo.DIM_Cliente WHERE ClienteKey <> -1
GROUP BY TipoNPS ORDER BY Clientes DESC;

SELECT CanalPreferido, COUNT(*) AS Clientes
FROM dbo.DIM_Cliente WHERE ClienteKey <> -1
GROUP BY CanalPreferido ORDER BY Clientes DESC;

/* NPS de la base de clientes = % Promotores - % Detractores (entre los que respondieron) */
SELECT CAST(100.0 * (SUM(CASE WHEN TipoNPS = N'Promotor'  THEN 1 ELSE 0 END)
                   - SUM(CASE WHEN TipoNPS = N'Detractor' THEN 1 ELSE 0 END))
            / NULLIF(SUM(CASE WHEN TipoNPS <> N'Sin encuesta' THEN 1 ELSE 0 END), 0) AS DECIMAL(5,1)) AS NPS
FROM dbo.DIM_Cliente WHERE ClienteKey <> -1;

/* 4. Reporte de calidad de perfiles */
SELECT Transformacion, Problema, RegistrosAfectados, ReglaAplicada
FROM dbo.ReporteCalidadDatos WHERE Fuente = N'Mongo · perfiles' ORDER BY ReporteID;
GO

/* =====================================================================
   RESUMEN FINAL
   ===================================================================== */
SELECT SUM(CASE WHEN Resultado = N'OK' THEN 1 ELSE 0 END)    AS ControlesOK,
       SUM(CASE WHEN Resultado = N'ERROR' THEN 1 ELSE 0 END) AS ControlesERROR
FROM stg.validacion_resultado;

DECLARE @err INT = (SELECT COUNT(*) FROM stg.validacion_resultado WHERE Resultado = N'ERROR');
IF @err > 0 PRINT CONCAT(N'ATENCIÓN: ', @err, N' control(es) en ERROR. Revise la sección 8 (y la 7 para ventas).');
ELSE PRINT N'Validación terminada: todos los controles de la sección 8 están en OK. Revise también que la sección 7 diga OK.';
GO
