/* =====================================================================
   04_vistas.sql  -  Vistas de lectura reutilizable
     vw_CatalogoDisponible   catálogo de la tienda con precio final y reseñas
     vw_InventarioBajoMinimo alerta de existencias bajas
     vw_VentasDetalle        base de todos los reportes de ventas
     vw_ResumenPedidos       un renglón por pedido (historial y R10)
     vw_ResumenComercial     indicadores del panel del administrador
   ===================================================================== */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE TiendaTechDB;
GO

/* Productos que la tienda puede mostrar: activos, con marca y categoría activas.
   Incluye la mejor promoción vigente HOY, el precio final, la existencia,
   la calificación promedio y la imagen principal. */
CREATE OR ALTER VIEW dbo.vw_CatalogoDisponible
AS
SELECT p.ProductoId, p.SKU, p.Nombre, p.Descripcion, p.Especificaciones,
       p.MarcaId, m.Nombre AS Marca, p.CategoriaId, c.Nombre AS Categoria,
       p.Precio,
       ISNULL(pm.Descuento, 0) AS DescuentoUnitario,
       p.Precio - ISNULL(pm.Descuento, 0) AS PrecioFinal,
       pm.Promocion,
       i.Existencia,
       CAST(CASE WHEN i.Existencia > 0 THEN 1 ELSE 0 END AS BIT) AS Disponible,
       p.Destacado,
       r.CalificacionPromedio,
       ISNULL(r.TotalResenas, 0) AS TotalResenas,
       img.Url AS ImagenUrl
FROM dbo.Producto p
JOIN dbo.Marca m ON m.MarcaId = p.MarcaId AND m.Activo = 1
JOIN dbo.Categoria c ON c.CategoriaId = p.CategoriaId AND c.Activo = 1
JOIN dbo.Inventario i ON i.ProductoId = p.ProductoId
LEFT JOIN dbo.ProductoImagen img ON img.ProductoId = p.ProductoId AND img.EsPrincipal = 1
OUTER APPLY dbo.fn_MejorPromocion(p.ProductoId, CAST(SYSDATETIME() AS DATE)) pm
OUTER APPLY (SELECT CAST(AVG(CAST(x.Calificacion AS DECIMAL(4,2))) AS DECIMAL(3,1)) AS CalificacionPromedio,
                    COUNT(*) AS TotalResenas
             FROM dbo.Resena x WHERE x.ProductoId = p.ProductoId AND x.Activo = 1) r
WHERE p.Activo = 1;
GO

/* Productos activos cuya existencia está por debajo del mínimo definido. */
CREATE OR ALTER VIEW dbo.vw_InventarioBajoMinimo
AS
SELECT p.ProductoId, p.SKU, p.Nombre, m.Nombre AS Marca, c.Nombre AS Categoria,
       i.Existencia, i.StockMinimo, i.StockMinimo - i.Existencia AS Faltante, p.Costo
FROM dbo.Inventario i
JOIN dbo.Producto p ON p.ProductoId = i.ProductoId
JOIN dbo.Marca m ON m.MarcaId = p.MarcaId
JOIN dbo.Categoria c ON c.CategoriaId = p.CategoriaId
WHERE p.Activo = 1 AND i.Existencia < i.StockMinimo;
GO

/* Líneas vendidas. Regla de todos los reportes: un pedido CANCELADO no es una
   venta, y el importe es el histórico guardado en el detalle (TotalLinea),
   nunca el precio actual del catálogo. El costo de envío no es venta de producto. */
CREATE OR ALTER VIEW dbo.vw_VentasDetalle
AS
SELECT o.PedidoId, o.FechaPedido, YEAR(o.FechaPedido) AS Anio, MONTH(o.FechaPedido) AS Mes,
       o.ClienteId, cl.Nombre + N' ' + cl.Apellidos AS Cliente,
       d.ProductoId, p.SKU, p.Nombre AS Producto,
       p.MarcaId, m.Nombre AS Marca, p.CategoriaId, c.Nombre AS Categoria,
       d.Cantidad, d.PrecioUnitario, d.DescuentoUnitario, d.CostoUnitario,
       d.TotalLinea AS Importe,
       CAST(d.Cantidad * d.CostoUnitario AS DECIMAL(14,2)) AS CostoTotal
FROM dbo.Pedido o
JOIN dbo.DetallePedido d ON d.PedidoId = o.PedidoId
JOIN dbo.Cliente cl ON cl.ClienteId = o.ClienteId
JOIN dbo.Producto p ON p.ProductoId = d.ProductoId
JOIN dbo.Marca m ON m.MarcaId = p.MarcaId
JOIN dbo.Categoria c ON c.CategoriaId = p.CategoriaId
WHERE o.EstadoId <> 6;   -- 6 = Cancelado
GO

/* Un renglón por pedido, con su cliente, estado, número de líneas y totales. */
CREATE OR ALTER VIEW dbo.vw_ResumenPedidos
AS
SELECT o.PedidoId, o.FechaPedido, o.EstadoId, e.Nombre AS Estado,
       o.ClienteId, cl.Nombre + N' ' + cl.Apellidos AS Cliente, u.Correo,
       x.Lineas, x.Unidades, o.Subtotal, o.DescuentoTotal, o.CostoEnvio, o.Total
FROM dbo.Pedido o
JOIN dbo.EstadoPedido e ON e.EstadoId = o.EstadoId
JOIN dbo.Cliente cl ON cl.ClienteId = o.ClienteId
JOIN dbo.Usuario u ON u.UsuarioId = cl.UsuarioId
CROSS APPLY (SELECT COUNT(*) AS Lineas, SUM(d.Cantidad) AS Unidades
             FROM dbo.DetallePedido d WHERE d.PedidoId = o.PedidoId) x;
GO

/* Indicadores generales (una sola fila) para el panel del administrador. */
CREATE OR ALTER VIEW dbo.vw_ResumenComercial
AS
SELECT
    (SELECT ISNULL(SUM(Importe), 0) FROM dbo.vw_VentasDetalle) AS VentasTotales,
    (SELECT COUNT(DISTINCT PedidoId) FROM dbo.vw_VentasDetalle) AS PedidosVendidos,
    (SELECT CAST(ISNULL(SUM(Importe) / NULLIF(COUNT(DISTINCT PedidoId), 0), 0) AS DECIMAL(14,2)) FROM dbo.vw_VentasDetalle) AS TicketPromedio,
    (SELECT COUNT(*) FROM dbo.Pedido WHERE EstadoId = 1) AS PedidosPendientes,
    (SELECT COUNT(*) FROM dbo.Pedido WHERE EstadoId IN (2, 3, 4)) AS PedidosEnProceso,
    (SELECT COUNT(*) FROM dbo.Pedido WHERE EstadoId = 6) AS PedidosCancelados,
    (SELECT COUNT(*) FROM dbo.Cliente WHERE Activo = 1) AS ClientesActivos,
    (SELECT COUNT(*) FROM dbo.Producto WHERE Activo = 1) AS ProductosActivos,
    (SELECT COUNT(*) FROM dbo.vw_InventarioBajoMinimo) AS ProductosBajoMinimo,
    (SELECT COUNT(*) FROM dbo.Promocion
     WHERE Activo = 1 AND CAST(SYSDATETIME() AS DATE) BETWEEN FechaInicio AND FechaFin) AS PromocionesVigentes;
GO
PRINT '04_vistas.sql: vistas creadas.';
GO
