/* =====================================================================
   09_evidencia_indices.sql  -  Evidencia de la utilidad de los índices
   (script opcional de demostración; no forma parte de la instalación)

   Con 36 pedidos cualquier consulta lee 2 páginas, así que no se nota la
   diferencia. Este script:
     1. Abre una transacción y carga un volumen temporal
        (40 000 pedidos y 120 000 líneas).
     2. Ejecuta cada consulta dos veces: forzando el recorrido del índice
        agrupado (como si el índice no existiera) y dejando que el optimizador
        use el índice no agrupado. SET STATISTICS IO muestra las lecturas
        lógicas de cada una en la pestaña "Messages".
     3. Hace ROLLBACK: la base queda exactamente como estaba.

   Ejecutar en SSMS con "Include Actual Execution Plan" (Ctrl+M) para ver
   además el plan: Clustered Index Scan contra Index Seek.
   ===================================================================== */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE TiendaTechDB;
GO
DECLARE @MaxPedido INT = (SELECT MAX(PedidoId) FROM dbo.Pedido);

BEGIN TRANSACTION;

/* ---------- 1. Volumen temporal ---------- */
;WITH N AS (
    SELECT TOP (40000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.Pedido (ClienteId, DireccionId, EstadoId, FechaPedido, Subtotal, DescuentoTotal, CostoEnvio)
SELECT n % 20 + 1, n % 20 + 1, 5, DATEADD(MINUTE, -n * 13, '2026-11-01T00:00:00'), 100000, 0, 2500
FROM N;

INSERT INTO dbo.DetallePedido (PedidoId, ProductoId, Cantidad, PrecioUnitario, DescuentoUnitario, CostoUnitario)
SELECT o.PedidoId, (o.PedidoId * 7 + k.k * 11) % 50 + 1, 1, 50000, 0, 40000
FROM dbo.Pedido o CROSS JOIN (VALUES (1), (2), (3)) k(k)
WHERE o.PedidoId > @MaxPedido;

UPDATE STATISTICS dbo.Pedido;
UPDATE STATISTICS dbo.DetallePedido;

SELECT (SELECT COUNT(*) FROM dbo.Pedido) AS PedidosEnPrueba, (SELECT COUNT(*) FROM dbo.DetallePedido) AS LineasEnPrueba;

SET STATISTICS IO ON;

/* ---------- 2. Comparaciones ---------- */
PRINT '';
PRINT '=== IX_Pedido_Cliente_Fecha: historial de pedidos de un cliente ===';
PRINT '--- A) Sin el índice (recorrido del índice agrupado):';
SELECT TOP (20) PedidoId, FechaPedido, EstadoId, Subtotal
FROM dbo.Pedido WITH (INDEX (PK_Pedido))
WHERE ClienteId = 7 ORDER BY FechaPedido DESC;
PRINT '--- B) Con IX_Pedido_Cliente_Fecha:';
SELECT TOP (20) PedidoId, FechaPedido, EstadoId, Subtotal
FROM dbo.Pedido
WHERE ClienteId = 7 ORDER BY FechaPedido DESC;

PRINT '';
PRINT '=== IX_Pedido_Fecha: reportes por rango de fechas (R4, R9, R10) ===';
PRINT '--- A) Sin el índice:';
SELECT COUNT(*) AS Pedidos FROM dbo.Pedido WITH (INDEX (PK_Pedido))
WHERE FechaPedido >= '2026-10-01' AND FechaPedido < '2026-10-08' AND EstadoId <> 6;
PRINT '--- B) Con IX_Pedido_Fecha:';
SELECT COUNT(*) AS Pedidos FROM dbo.Pedido
WHERE FechaPedido >= '2026-10-01' AND FechaPedido < '2026-10-08' AND EstadoId <> 6;

PRINT '';
PRINT '=== IX_DetallePedido_Producto: ventas de un producto (R5, R7) ===';
PRINT '--- A) Sin el índice:';
SELECT SUM(Cantidad) AS Unidades, SUM(Cantidad * (PrecioUnitario - DescuentoUnitario)) AS Ingresos
FROM dbo.DetallePedido WITH (INDEX (PK_DetallePedido)) WHERE ProductoId = 23;
PRINT '--- B) Con IX_DetallePedido_Producto:';
SELECT SUM(Cantidad) AS Unidades, SUM(Cantidad * (PrecioUnitario - DescuentoUnitario)) AS Ingresos
FROM dbo.DetallePedido WHERE ProductoId = 23;

PRINT '';
PRINT '=== IX_Producto_Categoria: catálogo filtrado por categoría ===';
PRINT '--- A) Sin el índice:';
SELECT ProductoId, Nombre, Precio FROM dbo.Producto WITH (INDEX (PK_Producto)) WHERE CategoriaId = 2 AND Activo = 1;
PRINT '--- B) Con IX_Producto_Categoria:';
SELECT ProductoId, Nombre, Precio FROM dbo.Producto WHERE CategoriaId = 2 AND Activo = 1;

SET STATISTICS IO OFF;

/* ---------- 3. Dejar todo como estaba ---------- */
ROLLBACK TRANSACTION;
DBCC CHECKIDENT ('dbo.Pedido', RESEED, @MaxPedido) WITH NO_INFOMSGS;
DECLARE @MaxHist INT = (SELECT ISNULL(MAX(HistorialId), 0) FROM dbo.HistorialEstadoPedido);
DBCC CHECKIDENT ('dbo.HistorialEstadoPedido', RESEED, @MaxHist) WITH NO_INFOMSGS;
UPDATE STATISTICS dbo.Pedido;
UPDATE STATISTICS dbo.DetallePedido;
SELECT (SELECT COUNT(*) FROM dbo.Pedido) AS PedidosAlFinal, (SELECT COUNT(*) FROM dbo.DetallePedido) AS LineasAlFinal;
PRINT 'Evidencia terminada: los datos temporales se revirtieron.';
GO
