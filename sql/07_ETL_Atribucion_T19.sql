/* =====================================================================
   07 · T19 · ATRIBUCIÓN DE VENTAS A CAMPAÑAS  [TU PARTE]
   Regla: una venta se atribuye a la campaña cuyo CLIC (del mismo cliente) ocurrió
   hasta 7 días antes del pedido ("ultimo clic" dentro de la ventana de 7 dias).
     - Ventana: fecha del clic <= fecha del pedido <= fecha del clic + 7 dias
       (por dia: el pedido solo guarda la fecha, no se compara la hora).
     - Si hay varios clics candidatos gana el MAS RECIENTE (desempate: mayor InteraccionKey).
     - Se atribuye el pedido completo: todas sus lineas reciben la misma campaña.
     - Clientes desconocidos (-1) o clics sin campaña valida no atribuyen.
     - Sin clic en la ventana -> CampanaAtribuidaKey = -1 (sin atribucion).
   Escribe en FACT_Ventas.CampanaAtribuidaKey. Re-ejecutable.
   REQUISITOS: 04 (FACT_Ventas) y 06 (FACT_InteraccionMarketing y stg.Interaccion_Evento).
   ===================================================================== */
USE FINALBI_DW_GrupoN;
GO

DECLARE @VentanaDias INT = 7;

/* 1. Clics: uno por interaccion (primer clic), en hora Colombia */
DROP TABLE IF EXISTS stg.Atribucion_Clics;
SELECT f.InteraccionKey, f.ClienteKey, f.CampanaKey,
       MIN(e.FechaColombia)                 AS FechaHoraClic,
       CAST(MIN(e.FechaColombia) AS DATE)   AS FechaClic
INTO stg.Atribucion_Clics
FROM dbo.FACT_InteraccionMarketing f
JOIN stg.Interaccion_Evento e ON e.InteraccionID = f.InteraccionID AND e.TipoEvento = N'clic'
WHERE f.ClienteKey <> -1 AND f.CampanaKey <> -1 AND e.FechaColombia IS NOT NULL
GROUP BY f.InteraccionKey, f.ClienteKey, f.CampanaKey;

/* 2. Pedidos (un cliente y una fecha por pedido) */
DROP TABLE IF EXISTS stg.Atribucion_Pedido;
;WITH pedidos AS (
    SELECT v.NumeroPedido, v.ClienteKey, MIN(t.Fecha) AS FechaPedido
    FROM dbo.FACT_Ventas v
    JOIN dbo.DIM_Tiempo t ON t.TiempoKey = v.TiempoKey
    WHERE v.ClienteKey <> -1
    GROUP BY v.NumeroPedido, v.ClienteKey
),
candidatos AS (
    SELECT p.NumeroPedido, c.CampanaKey, c.InteraccionKey, c.FechaClic,
           ROW_NUMBER() OVER (PARTITION BY p.NumeroPedido
                              ORDER BY c.FechaHoraClic DESC, c.InteraccionKey DESC) AS rn
    FROM pedidos p
    JOIN stg.Atribucion_Clics c
      ON c.ClienteKey = p.ClienteKey
     AND p.FechaPedido BETWEEN c.FechaClic AND DATEADD(DAY, @VentanaDias, c.FechaClic)
)
SELECT NumeroPedido, CampanaKey, InteraccionKey, FechaClic
INTO stg.Atribucion_Pedido
FROM candidatos WHERE rn = 1;

/* 3. Aplicar a FACT_Ventas */
UPDATE dbo.FACT_Ventas SET CampanaAtribuidaKey = -1;

UPDATE v
SET v.CampanaAtribuidaKey = a.CampanaKey
FROM dbo.FACT_Ventas v
JOIN stg.Atribucion_Pedido a ON a.NumeroPedido = v.NumeroPedido;
GO

/* Comprobaciones (captura) */
SELECT N'Lineas de venta' AS Concepto, COUNT(*) AS Valor FROM dbo.FACT_Ventas
UNION ALL SELECT N'  atribuidas a una campaña', COUNT(*) FROM dbo.FACT_Ventas WHERE CampanaAtribuidaKey <> -1
UNION ALL SELECT N'  sin atribución (-1)',       COUNT(*) FROM dbo.FACT_Ventas WHERE CampanaAtribuidaKey = -1
UNION ALL SELECT N'Pedidos atribuidos',          COUNT(*) FROM stg.Atribucion_Pedido
UNION ALL SELECT N'Clics usables (cliente y campaña conocidos)', COUNT(*) FROM stg.Atribucion_Clics;

/* Venta atribuida, presupuesto y ROI por campaña: ROI = (venta atribuida - presupuesto) / presupuesto */
SELECT c.CampanaID, c.NombreCampana, c.Presupuesto,
       COUNT(DISTINCT v.NumeroPedido)  AS PedidosAtribuidos,
       SUM(v.TotalVenta)               AS VentaAtribuida,
       CAST((SUM(v.TotalVenta) - c.Presupuesto) / NULLIF(c.Presupuesto, 0) AS DECIMAL(9,2)) AS ROI
FROM dbo.FACT_Ventas v
JOIN dbo.DIM_Campana c ON c.CampanaKey = v.CampanaAtribuidaKey
WHERE v.CampanaAtribuidaKey <> -1
GROUP BY c.CampanaID, c.NombreCampana, c.Presupuesto
ORDER BY c.CampanaID;

/* Black Friday 2024 vs 2025 (pregunta de negocio del enunciado) */
SELECT c.CampanaID, c.NombreCampana, c.Presupuesto, SUM(v.TotalVenta) AS VentaAtribuida,
       CAST((SUM(v.TotalVenta) - c.Presupuesto) / NULLIF(c.Presupuesto, 0) AS DECIMAL(9,2)) AS ROI
FROM dbo.FACT_Ventas v
JOIN dbo.DIM_Campana c ON c.CampanaKey = v.CampanaAtribuidaKey
WHERE c.CampanaID IN (N'CMP-2024-11', N'CMP-2025-11')
GROUP BY c.CampanaID, c.NombreCampana, c.Presupuesto
ORDER BY c.CampanaID;
GO
