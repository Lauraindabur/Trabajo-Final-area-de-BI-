/* =====================================================================
   07 · T19 · ATRIBUCIÓN DE VENTAS A CAMPAÑAS  
   Regla: una venta se atribuye a la campaña cuyo CLIC (del mismo cliente) ocurrió
   hasta 7 días antes del pedido ("ultimo clic" dentro de la ventana de 7 dias).

     - Ventana: fecha del clic <= fecha del pedido <= fecha del clic + 7 dias
       (por dia: el pedido solo guarda la fecha, no se compara la hora).

     - Si hay varios clics candidatos gana el MAS RECIENTE (desempate: mayor InteraccionKey).

     - Se atribuye el pedido completo: todas sus lineas reciben la misma campaña.

     - Clientes desconocidos (-1) o clics sin campaña valida no atribuyen.

     - Sin clic en la ventana -> CampanaAtribuidaKey = -1 (sin atribucion).

   Escribe en FACT_Ventas.CampanaAtribuidaKey. 
   REQUISITOS: 04 (FACT_Ventas) y 06 (FACT_InteraccionMarketing y stg.Interaccion_Evento).
   ===================================================================== */
USE FINALBI_DW_GrupoN; -- bd donde se va a trabajar
GO

DECLARE @VentanaDias INT = 7; -- crear una variable con 7 que son los dias de la ventana, se hace en variable por si se quiere cambair

/* 1. Clics: uno por interaccion (primer clic), en hora Colombia -> quién hizo clic en qué campaña y cuándo? */
DROP TABLE IF EXISTS stg.Atribucion_Clics;
SELECT f.InteraccionKey, f.ClienteKey, f.CampanaKey,
       MIN(e.FechaColombia)                 AS FechaHoraClic,
       CAST(MIN(e.FechaColombia) AS DATE)   AS FechaClic
INTO stg.Atribucion_Clics -- Elige las columnas y guarda el resultado en una tabla nueva. 
FROM dbo.FACT_InteraccionMarketing f
JOIN stg.Interaccion_Evento e ON e.InteraccionID = f.InteraccionID AND e.TipoEvento = N'clic' -- join pq f sabe quien/que campaña -> e sabe cuando fue el click
WHERE f.ClienteKey <> -1 AND f.CampanaKey <> -1 AND e.FechaColombia IS NOT NULL --Descarta los clics donde no se sabe el cliente (-1), no se sabe la campaña (-1) o no hay fecha
GROUP BY f.InteraccionKey, f.ClienteKey, f.CampanaKey; -- porque se usa min

/* 2. Preparar los pedidos y escoger la campaña (¿quién compró y cuándo? y aplciar regla) */
DROP TABLE IF EXISTS stg.Atribucion_Pedido;
;WITH pedidos AS ( --cte (consulta temporal solo existe mientras la ejecucion no se guarda permanente)
    SELECT v.NumeroPedido, v.ClienteKey, MIN(t.Fecha) AS FechaPedido 
    FROM dbo.FACT_Ventas v -- tiene una fila por producto. Un pedido de 3 productos ocupa 3 filas.
    JOIN dbo.DIM_Tiempo t ON t.TiempoKey = v.TiempoKey --El JOIN da la fecha real. La fact solo guarda un número como 20251115
    WHERE v.ClienteKey <> -1 -- descartan clientes desconocidos
    GROUP BY v.NumeroPedido, v.ClienteKey
),
candidatos AS ( --une cada pedido con los clics que podrian explicaarlo
    SELECT p.NumeroPedido, c.CampanaKey, c.InteraccionKey, c.FechaClic,  -- si un pedido tiene varios clicks candidatos
           ROW_NUMBER() OVER (PARTITION BY p.NumeroPedido  --hacer grupos uno por pedido y numerarlos, ordenar la fecha, si = fecha desempata mas reciente
                              ORDER BY c.FechaHoraClic DESC, c.InteraccionKey DESC) AS rn
    FROM pedidos p
    JOIN stg.Atribucion_Clics c  -- regla
      ON c.ClienteKey = p.ClienteKey -- unir pedido con click -> si son del mismo cliente y el edido fue entre el dia del click y venta 7dias
     AND p.FechaPedido BETWEEN c.FechaClic AND DATEADD(DAY, @VentanaDias, c.FechaClic)
)
SELECT NumeroPedido, CampanaKey, InteraccionKey, FechaClic
INTO stg.Atribucion_Pedido
FROM candidatos WHERE rn = 1; -- se queda solo con el click 1 (mas reciente)

/* 3. Aplicar a FACT_Ventas */
UPDATE dbo.FACT_Ventas SET CampanaAtribuidaKey = -1;
 
UPDATE v --copiamos la campaña ganadora de pedido a las lineas de venta de ese peiddo en FACT_Ventas
SET v.CampanaAtribuidaKey = a.CampanaKey -- escribe la CampanaKey que viene de Atribucion_Pedido
FROM dbo.FACT_Ventas v
JOIN stg.Atribucion_Pedido a ON a.NumeroPedido = v.NumeroPedido; --Une las dos tablas por el número de pedido
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
