/* =====================================================================
   07_pruebas.sql  -  Casos de prueba obligatorios (sección 10 del enunciado)
   Cada prueba indica: datos iniciales, acción, resultado esperado y
   resultado obtenido. Al final se imprime una tabla con PASA / FALLA.

   Ejecutar:  sqlcmd -S .\SQLEXPRESS -E -C -f 65001 -W -i 07_pruebas.sql
   (o abrirlo en SSMS y presionar F5; los mensajes salen en "Messages").

   Las pruebas NO ensucian los datos de los reportes:
     - Las que modifican ventas o precios corren dentro de una transacción
       que al final se revierte (ROLLBACK).
     - La prueba 4 (cancelación) sí queda guardada: deja un pedido cancelado
       del cliente 20, que no cuenta como venta y cuyo inventario vuelve a
       su valor original.
   La prueba 10 (concurrencia) necesita dos sesiones: ver el final del script
   y pruebas/prueba_concurrencia.py.
   ===================================================================== */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
GO
USE TiendaTechDB;
GO
DECLARE @R TABLE (Num VARCHAR(4), Prueba NVARCHAR(70), Esperado NVARCHAR(120), Obtenido NVARCHAR(400), Resultado VARCHAR(5));
DECLARE @Admin INT = 1;                 -- admin@tiendatech.test
DECLARE @Cliente INT = 20, @UsuarioCliente INT = 21, @Direccion INT = 20;   -- cliente20: nunca ha comprado
DECLARE @PedidoId INT, @Mov INT, @Err INT, @Msg NVARCHAR(2048), @Tran INT, @n INT, @n2 INT;
DECLARE @E1 INT, @E2 INT, @E1d INT, @E2d INT, @Ok BIT;

/* ---------------------------------------------------------------------
   PRUEBA 1. Compra exitosa y descuento correcto del inventario.
   Datos: carrito con 2 x TEC-001 (id 23) y 3 x ALM-003 (id 41). Pago con tarjeta.
   Esperado: pedido Confirmado; existencias -2 y -3; 2 movimientos de SALIDA;
             encabezado = suma del detalle; pago APROBADO; carrito vacío.
   --------------------------------------------------------------------- */
PRINT '--- PRUEBA 1: compra exitosa ---';
BEGIN TRANSACTION;
BEGIN TRY
    SELECT @E1 = Existencia FROM dbo.Inventario WHERE ProductoId = 23;
    SELECT @E2 = Existencia FROM dbo.Inventario WHERE ProductoId = 41;
    EXEC dbo.usp_Carrito_Vaciar @ClienteId = @Cliente;
    EXEC dbo.usp_Carrito_Agregar @ClienteId = @Cliente, @ProductoId = 23, @Cantidad = 2;
    EXEC dbo.usp_Carrito_Agregar @ClienteId = @Cliente, @ProductoId = 41, @Cantidad = 3;
    SET @PedidoId = NULL;
    EXEC dbo.usp_Pedido_Confirmar @ClienteId = @Cliente, @DireccionId = @Direccion, @MetodoPagoId = 1, @PedidoId = @PedidoId OUTPUT;

    SELECT @E1d = Existencia FROM dbo.Inventario WHERE ProductoId = 23;
    SELECT @E2d = Existencia FROM dbo.Inventario WHERE ProductoId = 41;
    SELECT 'P1 encabezado' AS Evidencia, PedidoId, EstadoId, Subtotal, DescuentoTotal, CostoEnvio, Total FROM dbo.Pedido WHERE PedidoId = @PedidoId;
    SELECT 'P1 detalle' AS Evidencia, ProductoId, Cantidad, PrecioUnitario, DescuentoUnitario, CostoUnitario, TotalLinea FROM dbo.DetallePedido WHERE PedidoId = @PedidoId;
    SELECT 'P1 movimientos' AS Evidencia, ProductoId, Tipo, Cantidad, ExistenciaResultante, Motivo FROM dbo.MovimientoInventario WHERE PedidoId = @PedidoId;
    SELECT 'P1 historial' AS Evidencia, EstadoAnteriorId, EstadoNuevoId, UsuarioId, Comentario FROM dbo.HistorialEstadoPedido WHERE PedidoId = @PedidoId;

    SET @Ok = CASE WHEN @E1d = @E1 - 2 AND @E2d = @E2 - 3
        AND (SELECT COUNT(*) FROM dbo.MovimientoInventario WHERE PedidoId = @PedidoId AND Tipo = 'SALIDA') = 2
        AND (SELECT EstadoId FROM dbo.Pedido WHERE PedidoId = @PedidoId) = 2
        AND (SELECT Subtotal - DescuentoTotal FROM dbo.Pedido WHERE PedidoId = @PedidoId) = (SELECT SUM(TotalLinea) FROM dbo.DetallePedido WHERE PedidoId = @PedidoId)
        AND (SELECT COUNT(*) FROM dbo.Pago g JOIN dbo.Pedido o ON o.PedidoId = g.PedidoId WHERE g.PedidoId = @PedidoId AND g.Estado = 'APROBADO' AND g.Monto = o.Total) = 1
        AND (SELECT COUNT(*) FROM dbo.HistorialEstadoPedido WHERE PedidoId = @PedidoId) = 2
        AND NOT EXISTS (SELECT 1 FROM dbo.DetalleCarrito dc JOIN dbo.Carrito c ON c.CarritoId = dc.CarritoId WHERE c.ClienteId = @Cliente)
        THEN 1 ELSE 0 END;
    INSERT INTO @R VALUES ('1', N'Compra exitosa y descuento de inventario', N'Existencias -2 y -3; pedido Confirmado; todo concilia',
        FORMATMESSAGE(N'TEC-001: %d -> %d; ALM-003: %d -> %d; pedido #%d', @E1, @E1d, @E2, @E2d, @PedidoId), IIF(@Ok = 1, 'PASA', 'FALLA'));
END TRY
BEGIN CATCH
    INSERT INTO @R VALUES ('1', N'Compra exitosa y descuento de inventario', N'Sin errores', ERROR_MESSAGE(), 'FALLA');
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

/* ---------------------------------------------------------------------
   PRUEBA 2. Compra fallida por falta de existencias y comprobación de ROLLBACK.
   Datos: el cliente pone en el carrito TODA la existencia de ALM-004 (id 42);
          luego se vende 1 unidad por otro canal, así que ya no alcanza.
   Esperado: error 51003, no queda transacción abierta (@@TRANCOUNT = 0),
             no existe pedido nuevo y la existencia queda intacta.
   --------------------------------------------------------------------- */
PRINT '--- PRUEBA 2: compra fallida por falta de existencias ---';
SELECT @E1 = Existencia FROM dbo.Inventario WHERE ProductoId = 42;
SELECT @n = COUNT(*) FROM dbo.Pedido;
SELECT @Err = NULL, @Msg = NULL, @Tran = NULL;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.usp_Carrito_Vaciar @ClienteId = @Cliente;
    EXEC dbo.usp_Carrito_Agregar @ClienteId = @Cliente, @ProductoId = 42, @Cantidad = @E1;
    EXEC dbo.usp_Inventario_RegistrarMovimiento @ProductoId = 42, @Tipo = 'SALIDA', @Cantidad = 1, @UsuarioId = @Admin,
         @Motivo = N'Venta en tienda física (montaje de la prueba 2)', @MovimientoId = @Mov OUTPUT;
    EXEC dbo.usp_Pedido_Confirmar @ClienteId = @Cliente, @DireccionId = @Direccion, @MetodoPagoId = 1, @PedidoId = @PedidoId OUTPUT;
END TRY
BEGIN CATCH
    SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE(), @Tran = @@TRANCOUNT;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SELECT @E1d = Existencia FROM dbo.Inventario WHERE ProductoId = 42;
SELECT @n2 = COUNT(*) FROM dbo.Pedido;
PRINT ISNULL(@Msg, '(sin error)');
INSERT INTO @R VALUES ('2', N'Compra fallida por falta de existencias', N'Error 51003; @@TRANCOUNT = 0; sin pedido; existencia intacta',
    FORMATMESSAGE(N'Error %d; @@TRANCOUNT = %d; pedidos %d -> %d; existencia %d -> %d', ISNULL(@Err, 0), ISNULL(@Tran, -1), @n, @n2, @E1, @E1d),
    IIF(@Err = 51003 AND @Tran = 0 AND @n = @n2 AND @E1 = @E1d, 'PASA', 'FALLA'));

/* ---------------------------------------------------------------------
   PRUEBA 3. Pedido con dos productos, uno sin stock: no se afecta NINGÚN inventario.
   Datos: carrito con 1 x AUD-002 (id 34, con existencia) y 2 x ACC-003 (id 51, existencia 0).
          La línea agotada se inserta directo para simular que el producto se
          agotó cuando ya estaba en el carrito.
   Esperado: error 51003; la existencia de AUD-002 no cambia; no hay movimientos nuevos.
   --------------------------------------------------------------------- */
PRINT '--- PRUEBA 3: dos productos, uno sin stock ---';
SELECT @E1 = Existencia FROM dbo.Inventario WHERE ProductoId = 34;
SELECT @E2 = Existencia FROM dbo.Inventario WHERE ProductoId = 51;
SELECT @n = COUNT(*) FROM dbo.MovimientoInventario;
SELECT @Err = NULL, @Msg = NULL, @Tran = NULL;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.usp_Carrito_Vaciar @ClienteId = @Cliente;
    EXEC dbo.usp_Carrito_Agregar @ClienteId = @Cliente, @ProductoId = 34, @Cantidad = 1;
    INSERT INTO dbo.DetalleCarrito (CarritoId, ProductoId, Cantidad)
    SELECT CarritoId, 51, 2 FROM dbo.Carrito WHERE ClienteId = @Cliente;
    EXEC dbo.usp_Pedido_Confirmar @ClienteId = @Cliente, @DireccionId = @Direccion, @MetodoPagoId = 2, @PedidoId = @PedidoId OUTPUT;
END TRY
BEGIN CATCH
    SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE(), @Tran = @@TRANCOUNT;
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
SELECT @E1d = Existencia FROM dbo.Inventario WHERE ProductoId = 34;
SELECT @E2d = Existencia FROM dbo.Inventario WHERE ProductoId = 51;
SELECT @n2 = COUNT(*) FROM dbo.MovimientoInventario;
PRINT ISNULL(@Msg, '(sin error)');
INSERT INTO @R VALUES ('3', N'Dos productos, uno sin stock', N'Error 51003; ningún inventario afectado; sin movimientos',
    FORMATMESSAGE(N'Error %d; AUD-002: %d -> %d; ACC-003: %d -> %d; movimientos %d -> %d', ISNULL(@Err, 0), @E1, @E1d, @E2, @E2d, @n, @n2),
    IIF(@Err = 51003 AND @Tran = 0 AND @E1 = @E1d AND @E2 = @E2d AND @n = @n2, 'PASA', 'FALLA'));

/* ---------------------------------------------------------------------
   PRUEBA 4. Cancelación y reintegro; segundo intento sin reintegro duplicado.
   Datos: se crea un pedido real de 2 x TEC-001 (id 23) y se cancela dos veces.
   Esperado: 1.ª cancelación -> existencia vuelve al valor original, 1 movimiento
             de ENTRADA y pago REEMBOLSADO.
             2.ª cancelación -> error 51004, existencia igual, sigue habiendo 1 sola ENTRADA.
   (Esta prueba queda guardada: deja un pedido cancelado.)
   --------------------------------------------------------------------- */
PRINT '--- PRUEBA 4: cancelación y segundo intento ---';
SELECT @E1 = Existencia FROM dbo.Inventario WHERE ProductoId = 23;
SELECT @Err = NULL, @Msg = NULL, @PedidoId = NULL;
BEGIN TRY
    EXEC dbo.usp_Carrito_Vaciar @ClienteId = @Cliente;
    EXEC dbo.usp_Carrito_Agregar @ClienteId = @Cliente, @ProductoId = 23, @Cantidad = 2;
    EXEC dbo.usp_Pedido_Confirmar @ClienteId = @Cliente, @DireccionId = @Direccion, @MetodoPagoId = 1, @PedidoId = @PedidoId OUTPUT;
    SELECT @E2 = Existencia FROM dbo.Inventario WHERE ProductoId = 23;           -- después de comprar
    EXEC dbo.usp_Pedido_Cancelar @PedidoId = @PedidoId, @UsuarioId = @UsuarioCliente, @Motivo = N'Prueba 4: primera cancelación';
    SELECT @E1d = Existencia FROM dbo.Inventario WHERE ProductoId = 23;          -- después de cancelar
    SELECT @n = COUNT(*) FROM dbo.MovimientoInventario WHERE PedidoId = @PedidoId AND Tipo = 'ENTRADA';
    INSERT INTO @R VALUES ('4a', N'Cancelación y reintegro de existencias', N'Existencia vuelve al valor original; 1 ENTRADA; pago REEMBOLSADO',
        FORMATMESSAGE(N'Pedido #%d: existencia %d -> %d (compra) -> %d (cancelación); entradas: %d; pago: %s', @PedidoId, @E1, @E2, @E1d, @n,
                      (SELECT Estado FROM dbo.Pago WHERE PedidoId = @PedidoId)),
        IIF(@E2 = @E1 - 2 AND @E1d = @E1 AND @n = 1 AND (SELECT Estado FROM dbo.Pago WHERE PedidoId = @PedidoId) = 'REEMBOLSADO'
            AND (SELECT EstadoId FROM dbo.Pedido WHERE PedidoId = @PedidoId) = 6, 'PASA', 'FALLA'));
END TRY
BEGIN CATCH
    INSERT INTO @R VALUES ('4a', N'Cancelación y reintegro de existencias', N'Sin errores', ERROR_MESSAGE(), 'FALLA');
END CATCH

BEGIN TRY
    EXEC dbo.usp_Pedido_Cancelar @PedidoId = @PedidoId, @UsuarioId = @UsuarioCliente, @Motivo = N'Prueba 4: segunda cancelación';
END TRY
BEGIN CATCH
    SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE();
END CATCH
SELECT @E2d = Existencia FROM dbo.Inventario WHERE ProductoId = 23;
SELECT @n2 = COUNT(*) FROM dbo.MovimientoInventario WHERE PedidoId = @PedidoId AND Tipo = 'ENTRADA';
PRINT ISNULL(@Msg, '(sin error)');
SELECT 'P4 movimientos del pedido' AS Evidencia, Tipo, Cantidad, ExistenciaResultante, Motivo FROM dbo.MovimientoInventario WHERE PedidoId = @PedidoId ORDER BY MovimientoId;
INSERT INTO @R VALUES ('4b', N'Segunda cancelación: sin reintegro duplicado', N'Error 51004; existencia igual; sigue 1 sola ENTRADA',
    FORMATMESSAGE(N'Error %d; existencia %d -> %d; entradas: %d', ISNULL(@Err, 0), @E1d, @E2d, @n2),
    IIF(@Err = 51004 AND @E2d = @E1d AND @n2 = 1, 'PASA', 'FALLA'));

/* ---------------------------------------------------------------------
   PRUEBA 5. Transición de estado inválida.
   Datos: pedido #1 (Entregado) y pedido #30 (Enviado).
   Esperado: Entregado -> Pendiente rechazado (51004); cancelar un pedido
             Enviado rechazado (51004). Los estados no cambian.
   --------------------------------------------------------------------- */
PRINT '--- PRUEBA 5: transición inválida ---';
SELECT @Err = NULL, @Msg = NULL;
BEGIN TRY
    EXEC dbo.usp_Pedido_CambiarEstado @PedidoId = 1, @NuevoEstadoId = 1, @UsuarioId = @Admin, @Comentario = N'Prueba 5';
END TRY
BEGIN CATCH SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE(); END CATCH
PRINT ISNULL(@Msg, '(sin error)');
INSERT INTO @R VALUES ('5a', N'Transición inválida: Entregado -> Pendiente', N'Error 51004; el pedido sigue Entregado',
    FORMATMESSAGE(N'Error %d; estado actual del pedido #1: %d', ISNULL(@Err, 0), (SELECT CAST(EstadoId AS INT) FROM dbo.Pedido WHERE PedidoId = 1)),
    IIF(@Err = 51004 AND (SELECT EstadoId FROM dbo.Pedido WHERE PedidoId = 1) = 5, 'PASA', 'FALLA'));

SELECT @Err = NULL, @Msg = NULL;
BEGIN TRY
    EXEC dbo.usp_Pedido_Cancelar @PedidoId = 30, @UsuarioId = @Admin, @Motivo = N'Prueba 5: cancelar un pedido ya enviado';
END TRY
BEGIN CATCH SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE(); END CATCH
PRINT ISNULL(@Msg, '(sin error)');
INSERT INTO @R VALUES ('5b', N'Transición inválida: cancelar pedido Enviado', N'Error 51004; el pedido sigue Enviado',
    FORMATMESSAGE(N'Error %d; estado actual del pedido #30: %d', ISNULL(@Err, 0), (SELECT CAST(EstadoId AS INT) FROM dbo.Pedido WHERE PedidoId = 30)),
    IIF(@Err = 51004 AND (SELECT EstadoId FROM dbo.Pedido WHERE PedidoId = 30) = 4, 'PASA', 'FALLA'));

/* ---------------------------------------------------------------------
   PRUEBA 6. Cambio de precio sin modificar el precio histórico de pedidos.
   Datos: la categoría Laptops sube 10 %. El pedido #1 ya tiene laptops vendidas.
   Esperado: Producto.Precio cambia; DetallePedido.PrecioUnitario y el total de
             ventas históricas NO cambian.
   --------------------------------------------------------------------- */
PRINT '--- PRUEBA 6: precio histórico ---';
DECLARE @VentasAntes DECIMAL(18,2), @VentasDespues DECIMAL(18,2), @PrecioAntes DECIMAL(18,2), @PrecioDespues DECIMAL(18,2), @CatLaptops INT;
SELECT @CatLaptops = CategoriaId FROM dbo.Categoria WHERE Nombre = N'Laptops';
SELECT @VentasAntes = SUM(d.Cantidad * d.PrecioUnitario) FROM dbo.DetallePedido d JOIN dbo.Producto p ON p.ProductoId = d.ProductoId WHERE p.CategoriaId = @CatLaptops;
SELECT @PrecioAntes = SUM(Precio) FROM dbo.Producto WHERE CategoriaId = @CatLaptops;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.usp_Producto_AjustarPrecioCategoria @CategoriaId = @CatLaptops, @Porcentaje = 10, @UsuarioId = @Admin, @Afectados = @n OUTPUT;
    SELECT @VentasDespues = SUM(d.Cantidad * d.PrecioUnitario) FROM dbo.DetallePedido d JOIN dbo.Producto p ON p.ProductoId = d.ProductoId WHERE p.CategoriaId = @CatLaptops;
    SELECT @PrecioDespues = SUM(Precio) FROM dbo.Producto WHERE CategoriaId = @CatLaptops;
    SELECT TOP (5) 'P6 precio catálogo vs histórico' AS Evidencia, p.SKU, p.Precio AS PrecioCatalogoNuevo, d.PrecioUnitario AS PrecioHistoricoPedido, d.PedidoId
    FROM dbo.DetallePedido d JOIN dbo.Producto p ON p.ProductoId = d.ProductoId WHERE p.CategoriaId = @CatLaptops ORDER BY d.PedidoId;
    INSERT INTO @R VALUES ('6', N'Cambio de precio sin alterar pedidos anteriores', N'Catálogo +10 %; importe histórico idéntico',
        N'Productos modificados: ' + CAST(@n AS NVARCHAR(10)) + N'; suma de precios de catálogo ' + FORMAT(@PrecioAntes, 'N0') + N' -> ' + FORMAT(@PrecioDespues, 'N0')
        + N'; ventas históricas ' + FORMAT(@VentasAntes, 'N0') + N' -> ' + FORMAT(@VentasDespues, 'N0'),
        IIF(@PrecioDespues > @PrecioAntes AND @VentasAntes = @VentasDespues AND @n > 1, 'PASA', 'FALLA'));
END TRY
BEGIN CATCH
    INSERT INTO @R VALUES ('6', N'Cambio de precio sin alterar pedidos anteriores', N'Sin errores', ERROR_MESSAGE(), 'FALLA');
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

/* ---------------------------------------------------------------------
   PRUEBA 7. Clave o valor duplicado: lo rechaza la BASE DE DATOS.
   7a: el procedimiento valida y devuelve un mensaje claro (51002).
   7b y 7c: INSERT directo, saltándose los procedimientos: lo detiene la
            restricción UNIQUE (error 2627).
   7d: CHECK impide existencia negativa (error 547).
   --------------------------------------------------------------------- */
PRINT '--- PRUEBA 7: duplicados y restricciones ---';
SELECT @Err = NULL, @Msg = NULL;
BEGIN TRY EXEC dbo.usp_Marca_Crear @Nombre = N'Apple', @PaisOrigen = NULL, @MarcaId = @n OUTPUT; END TRY
BEGIN CATCH SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE(); END CATCH
PRINT ISNULL(@Msg, '(sin error)');
INSERT INTO @R VALUES ('7a', N'Marca duplicada vía procedimiento', N'Error 51002', FORMATMESSAGE(N'Error %d: %s', ISNULL(@Err, 0), ISNULL(@Msg, N'')), IIF(@Err = 51002, 'PASA', 'FALLA'));

SELECT @Err = NULL, @Msg = NULL;
BEGIN TRY
    INSERT INTO dbo.Producto (SKU, Nombre, MarcaId, CategoriaId, Precio, Costo) VALUES ('LAP-001', N'SKU repetido', 1, 1, 1000, 500);
END TRY
BEGIN CATCH SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE(); END CATCH
PRINT ISNULL(@Msg, '(sin error)');
INSERT INTO @R VALUES ('7b', N'SKU duplicado con INSERT directo', N'Error 2627 (UQ_Producto_SKU)', FORMATMESSAGE(N'Error %d: %s', ISNULL(@Err, 0), LEFT(ISNULL(@Msg, N''), 110)), IIF(@Err = 2627, 'PASA', 'FALLA'));

SELECT @Err = NULL, @Msg = NULL;
BEGIN TRY
    INSERT INTO dbo.Resena (ClienteId, ProductoId, Calificacion)
    SELECT TOP (1) ClienteId, ProductoId, 5 FROM dbo.Resena ORDER BY ResenaId;
END TRY
BEGIN CATCH SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE(); END CATCH
PRINT ISNULL(@Msg, '(sin error)');
INSERT INTO @R VALUES ('7c', N'Reseña duplicada con INSERT directo', N'Error 2627 (UQ_Resena_Cliente_Producto)', FORMATMESSAGE(N'Error %d: %s', ISNULL(@Err, 0), LEFT(ISNULL(@Msg, N''), 110)), IIF(@Err = 2627, 'PASA', 'FALLA'));

SELECT @Err = NULL, @Msg = NULL;
BEGIN TRY UPDATE dbo.Inventario SET Existencia = -1 WHERE ProductoId = 1; END TRY
BEGIN CATCH SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE(); END CATCH
PRINT ISNULL(@Msg, '(sin error)');
INSERT INTO @R VALUES ('7d', N'Existencia negativa con UPDATE directo', N'Error 547 (CK_Inventario_Existencia)', FORMATMESSAGE(N'Error %d: %s', ISNULL(@Err, 0), LEFT(ISNULL(@Msg, N''), 110)), IIF(@Err = 547, 'PASA', 'FALLA'));

/* ---------------------------------------------------------------------
   PRUEBA 8. Triggers de auditoría ante una actualización de VARIAS filas.
   8a: un solo UPDATE cambia el precio de todos los productos Logitech
       -> una fila de auditoría por cada producto.
       Además un UPDATE que deja el mismo precio no genera auditoría.
   8b: un solo UPDATE pasa todos los pedidos Confirmados a En preparación
       -> una fila de historial por cada pedido.
   --------------------------------------------------------------------- */
PRINT '--- PRUEBA 8: triggers multi-fila ---';
DECLARE @Filas INT, @Aud INT, @AudSinCambio INT, @MarcaLogi INT, @MaxAud INT, @MaxHist INT;
SELECT @MarcaLogi = MarcaId FROM dbo.Marca WHERE Nombre = N'Logitech';
BEGIN TRANSACTION;
BEGIN TRY
    SELECT @MaxAud = ISNULL(MAX(AuditoriaId), 0) FROM dbo.AuditoriaPrecio;
    UPDATE dbo.Producto SET Precio = Precio + 1000 WHERE MarcaId = @MarcaLogi;
    SET @Filas = @@ROWCOUNT;
    SELECT @Aud = COUNT(*) FROM dbo.AuditoriaPrecio WHERE AuditoriaId > @MaxAud;
    SELECT 'P8a auditoría de precios' AS Evidencia, a.ProductoId, a.PrecioAnterior, a.PrecioNuevo, a.Fecha, a.UsuarioId, a.UsuarioBD
    FROM dbo.AuditoriaPrecio a WHERE a.AuditoriaId > @MaxAud;

    SELECT @MaxAud = ISNULL(MAX(AuditoriaId), 0) FROM dbo.AuditoriaPrecio;
    UPDATE dbo.Producto SET Precio = Precio WHERE MarcaId = @MarcaLogi;          -- mismo precio: no debe auditar
    SELECT @AudSinCambio = COUNT(*) FROM dbo.AuditoriaPrecio WHERE AuditoriaId > @MaxAud;

    INSERT INTO @R VALUES ('8a', N'Trigger de auditoría de precios (varias filas)', N'Una fila de auditoría por producto; 0 si el precio no cambia',
        FORMATMESSAGE(N'Filas actualizadas: %d; filas auditadas: %d; auditadas sin cambio real: %d', @Filas, @Aud, @AudSinCambio),
        IIF(@Filas > 1 AND @Aud = @Filas AND @AudSinCambio = 0, 'PASA', 'FALLA'));

    SELECT @MaxHist = ISNULL(MAX(HistorialId), 0) FROM dbo.HistorialEstadoPedido;
    UPDATE dbo.Pedido SET EstadoId = 3 WHERE EstadoId = 2;
    SET @Filas = @@ROWCOUNT;
    SELECT @Aud = COUNT(*) FROM dbo.HistorialEstadoPedido WHERE HistorialId > @MaxHist AND EstadoAnteriorId = 2 AND EstadoNuevoId = 3;
    SELECT 'P8b historial de estados' AS Evidencia, PedidoId, EstadoAnteriorId, EstadoNuevoId, Fecha, UsuarioBD FROM dbo.HistorialEstadoPedido WHERE HistorialId > @MaxHist;
    INSERT INTO @R VALUES ('8b', N'Trigger de historial de estados (varias filas)', N'Una fila de historial por pedido',
        FORMATMESSAGE(N'Pedidos actualizados: %d; filas de historial: %d', @Filas, @Aud), IIF(@Filas > 1 AND @Aud = @Filas, 'PASA', 'FALLA'));
END TRY
BEGIN CATCH
    INSERT INTO @R VALUES ('8', N'Triggers multi-fila', N'Sin errores', ERROR_MESSAGE(), 'FALLA');
END CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

/* ---------------------------------------------------------------------
   PRUEBA 9. Verificación de un reporte contra una consulta SQL independiente.
   El total de R4 (procedimiento, usa la vista) debe ser igual a la suma
   calculada directamente sobre las tablas base. En la defensa se compara
   además con lo que muestra la pantalla Reportes > R4.
   --------------------------------------------------------------------- */
PRINT '--- PRUEBA 9: verificación de reporte ---';
DECLARE @R4 TABLE (Mes INT, NombreMes NVARCHAR(20), Ventas DECIMAL(18,2), Pedidos INT, TicketPromedio DECIMAL(18,2));
DECLARE @TotalReporte DECIMAL(18,2), @TotalDirecto DECIMAL(18,2), @PedReporte INT, @PedDirecto INT;
INSERT INTO @R4 EXEC dbo.usp_Reporte_R4_EvolucionMensual @Anio = 2026;
SELECT @TotalReporte = SUM(Ventas), @PedReporte = SUM(Pedidos) FROM @R4;
SELECT @TotalDirecto = SUM(d.Cantidad * (d.PrecioUnitario - d.DescuentoUnitario)), @PedDirecto = COUNT(DISTINCT o.PedidoId)
FROM dbo.Pedido o JOIN dbo.DetallePedido d ON d.PedidoId = o.PedidoId
WHERE o.EstadoId <> 6 AND o.FechaPedido >= '2026-01-01' AND o.FechaPedido < '2027-01-01';
SELECT 'P9 reporte R4' AS Evidencia, * FROM @R4;
INSERT INTO @R VALUES ('9', N'Reporte R4 contra consulta directa', N'Totales idénticos',
    N'Reporte: ' + FORMAT(@TotalReporte, 'N2') + N' en ' + CAST(@PedReporte AS NVARCHAR(10)) + N' pedidos; consulta directa: '
    + FORMAT(@TotalDirecto, 'N2') + N' en ' + CAST(@PedDirecto AS NVARCHAR(10)) + N' pedidos',
    IIF(@TotalReporte = @TotalDirecto AND @PedReporte = @PedDirecto, 'PASA', 'FALLA'));

/* ---------------------------------------------------------------------
   PRUEBA 11. Inventario: no se permite existencia negativa y el libro de
   movimientos no se puede alterar.
   --------------------------------------------------------------------- */
PRINT '--- PRUEBA 11: reglas de inventario ---';
SELECT @Err = NULL, @Msg = NULL;
SELECT @E1 = Existencia FROM dbo.Inventario WHERE ProductoId = 1;
BEGIN TRY
    EXEC dbo.usp_Inventario_RegistrarMovimiento @ProductoId = 1, @Tipo = 'SALIDA', @Cantidad = 9999, @UsuarioId = @Admin, @Motivo = N'Prueba 11', @MovimientoId = @Mov OUTPUT;
END TRY
BEGIN CATCH SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE(); END CATCH
PRINT ISNULL(@Msg, '(sin error)');
SELECT @E1d = Existencia FROM dbo.Inventario WHERE ProductoId = 1;
INSERT INTO @R VALUES ('11a', N'Salida mayor que la existencia', N'Error 51003; existencia intacta',
    FORMATMESSAGE(N'Error %d; existencia %d -> %d', ISNULL(@Err, 0), @E1, @E1d), IIF(@Err = 51003 AND @E1 = @E1d, 'PASA', 'FALLA'));

SELECT @Err = NULL, @Msg = NULL;
BEGIN TRY UPDATE dbo.MovimientoInventario SET Cantidad = 999 WHERE MovimientoId = 1; END TRY
BEGIN CATCH SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE(); END CATCH
PRINT ISNULL(@Msg, '(sin error)');
INSERT INTO @R VALUES ('11b', N'Modificar un movimiento de inventario', N'Error 51006 (trigger)', FORMATMESSAGE(N'Error %d', ISNULL(@Err, 0)), IIF(@Err = 51006, 'PASA', 'FALLA'));
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

/* ---------------------------------------------------------------------
   PRUEBA 12. Reseñas: una por cliente y producto, y solo de lo comprado.
   --------------------------------------------------------------------- */
PRINT '--- PRUEBA 12: reglas de reseñas ---';
DECLARE @RCliente INT, @RProducto INT;
SELECT TOP (1) @RCliente = ClienteId, @RProducto = ProductoId FROM dbo.Resena WHERE Activo = 1 ORDER BY ResenaId;
SELECT @Err = NULL, @Msg = NULL;
BEGIN TRY EXEC dbo.usp_Resena_Crear @ClienteId = @RCliente, @ProductoId = @RProducto, @Calificacion = 4, @Comentario = N'Otra', @ResenaId = @n OUTPUT; END TRY
BEGIN CATCH SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE(); END CATCH
PRINT ISNULL(@Msg, '(sin error)');
INSERT INTO @R VALUES ('12a', N'Reseña duplicada vía procedimiento', N'Error 51002', FORMATMESSAGE(N'Error %d', ISNULL(@Err, 0)), IIF(@Err = 51002, 'PASA', 'FALLA'));

SELECT @Err = NULL, @Msg = NULL;
BEGIN TRY EXEC dbo.usp_Resena_Crear @ClienteId = 19, @ProductoId = 1, @Calificacion = 5, @Comentario = N'No lo compré', @ResenaId = @n OUTPUT; END TRY
BEGIN CATCH SELECT @Err = ERROR_NUMBER(), @Msg = ERROR_MESSAGE(); END CATCH
PRINT ISNULL(@Msg, '(sin error)');
INSERT INTO @R VALUES ('12b', N'Reseña de un producto no comprado', N'Error 51006', FORMATMESSAGE(N'Error %d', ISNULL(@Err, 0)), IIF(@Err = 51006, 'PASA', 'FALLA'));

/* ---------------------------------------------------------------------
   PRUEBA 13. Conciliación final: después de todas las pruebas, la existencia
   de cada producto sigue siendo igual a la suma de sus movimientos.
   --------------------------------------------------------------------- */
PRINT '--- PRUEBA 13: conciliación de inventario ---';
SELECT @n = COUNT(*) FROM dbo.Inventario i
WHERE i.Existencia <> (SELECT ISNULL(SUM(m.Cantidad), 0) FROM dbo.MovimientoInventario m WHERE m.ProductoId = i.ProductoId);
SELECT @n2 = COUNT(*) FROM dbo.Inventario WHERE Existencia < 0;
INSERT INTO @R VALUES ('13', N'Conciliación existencias vs movimientos', N'0 productos con diferencia; 0 existencias negativas',
    FORMATMESSAGE(N'Productos con diferencia: %d; existencias negativas: %d', @n, @n2), IIF(@n = 0 AND @n2 = 0, 'PASA', 'FALLA'));

EXEC dbo.usp_Carrito_Vaciar @ClienteId = @Cliente;

PRINT '';
PRINT '================ RESUMEN DE PRUEBAS ================';
SELECT Num, Prueba, Esperado, Obtenido, Resultado FROM @R;
SELECT COUNT(*) AS Pruebas, SUM(IIF(Resultado = 'PASA', 1, 0)) AS Pasan, SUM(IIF(Resultado = 'FALLA', 1, 0)) AS Fallan FROM @R;
GO

/* =====================================================================
   PRUEBA 10. Dos compras simultáneas con stock limitado, sin sobreventa.

   Opción A (automática):  python pruebas/prueba_concurrencia.py
     Lanza dos conexiones al mismo tiempo que intentan comprar la última
     unidad de un producto. Una confirma; la otra recibe el error 51003.

   Opción B (manual, dos ventanas de SSMS). Producto 55 (ACC-007).
   Clientes 19 y 20. Primero deje una sola unidad (como administrador):

     DECLARE @E INT = (SELECT Existencia FROM dbo.Inventario WHERE ProductoId = 55), @M INT;
     SET @E = @E - 1;
     IF @E > 0 EXEC dbo.usp_Inventario_RegistrarMovimiento 55, 'SALIDA', @E, 1, N'Prueba 10: dejar 1 unidad', @M OUTPUT;
     EXEC dbo.usp_Carrito_Vaciar 19;  EXEC dbo.usp_Carrito_Agregar 19, 55, 1;
     EXEC dbo.usp_Carrito_Vaciar 20;  EXEC dbo.usp_Carrito_Agregar 20, 55, 1;

   VENTANA 1 (deja la transacción abierta, con la fila de inventario bloqueada):
     BEGIN TRANSACTION;
     DECLARE @P INT;
     EXEC dbo.usp_Pedido_Confirmar @ClienteId = 19, @DireccionId = 19, @MetodoPagoId = 1, @PedidoId = @P OUTPUT;
     SELECT @P AS PedidoCreado;
     -- todavía NO ejecutar COMMIT

   VENTANA 2 (queda esperando, porque la fila está bloqueada):
     DECLARE @P INT;
     EXEC dbo.usp_Pedido_Confirmar @ClienteId = 20, @DireccionId = 20, @MetodoPagoId = 1, @PedidoId = @P OUTPUT;

   VENTANA 1:
     COMMIT TRANSACTION;

   Resultado: la ventana 2 se libera con el error 51003 "Existencia insuficiente".
   Verificación:
     SELECT Existencia FROM dbo.Inventario WHERE ProductoId = 55;          -- 0, nunca negativo
     SELECT COUNT(*) FROM dbo.DetallePedido d JOIN dbo.Pedido o ON o.PedidoId = d.PedidoId
     WHERE d.ProductoId = 55 AND o.FechaPedido >= CAST(GETDATE() AS DATE); -- 1 solo pedido
   ===================================================================== */
