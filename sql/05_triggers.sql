/* =====================================================================
   05_triggers.sql  -  Triggers
     TR_Producto_AuditoriaPrecio   auditoría de cambios de precio (multi-fila)
     TR_Pedido_HistorialEstado     historial de estados de pedidos (multi-fila)
     TR_MovimientoInventario_Inmutable  el libro de inventario no se edita ni borra

   Por qué triggers y no código en los procedimientos:
     - La auditoría debe quedar registrada aunque alguien cambie el dato con un
       UPDATE directo desde SSMS, saltándose los procedimientos.
     - No se usan para la lógica de compra: el checkout es una transacción
       explícita en usp_Pedido_Confirmar.
   Todos trabajan con las tablas inserted/deleted completas (sin variables
   escalares ni cursores), por lo que funcionan igual con 1 o con N filas.
   ===================================================================== */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE TiendaTechDB;
GO

/* ---------------------------------------------------------------------
   1. Auditoría de precios.
      Registra precio anterior, nuevo, fecha y usuario por CADA producto
      cuyo precio realmente cambió.
      Usuario de la aplicación: llega en SESSION_CONTEXT('UsuarioId'), que
      fijan los procedimientos. Usuario de base de datos: ORIGINAL_LOGIN().
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.TR_Producto_AuditoriaPrecio
ON dbo.Producto
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(Precio) RETURN;

    DECLARE @UsuarioId INT = TRY_CAST(SESSION_CONTEXT(N'UsuarioId') AS INT);
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId) SET @UsuarioId = NULL;

    INSERT INTO dbo.AuditoriaPrecio (ProductoId, PrecioAnterior, PrecioNuevo, UsuarioId)
    SELECT d.ProductoId, d.Precio, i.Precio, @UsuarioId
    FROM inserted i
    JOIN deleted d ON d.ProductoId = i.ProductoId
    WHERE i.Precio <> d.Precio;       -- solo las filas cuyo precio cambió de verdad
END
GO

/* ---------------------------------------------------------------------
   2. Historial de estados del pedido.
      INSERT: registra el estado inicial (anterior = NULL).
      UPDATE: registra cada cambio de estado con fecha y hora.
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.TR_Pedido_HistorialEstado
ON dbo.Pedido
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(EstadoId) RETURN;   -- en un INSERT, UPDATE(col) siempre es verdadero

    DECLARE @UsuarioId INT = TRY_CAST(SESSION_CONTEXT(N'UsuarioId') AS INT);
    DECLARE @Comentario NVARCHAR(250) = TRY_CAST(SESSION_CONTEXT(N'Comentario') AS NVARCHAR(250));
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId) SET @UsuarioId = NULL;

    INSERT INTO dbo.HistorialEstadoPedido (PedidoId, EstadoAnteriorId, EstadoNuevoId, UsuarioId, Comentario)
    SELECT i.PedidoId, d.EstadoId, i.EstadoId, @UsuarioId, @Comentario
    FROM inserted i
    LEFT JOIN deleted d ON d.PedidoId = i.PedidoId
    WHERE d.PedidoId IS NULL            -- pedido nuevo
       OR d.EstadoId <> i.EstadoId;     -- cambio real de estado
END
GO

/* ---------------------------------------------------------------------
   3. El libro de movimientos de inventario es inmutable.
      Un error se corrige con un movimiento de AJUSTE, nunca editando o
      borrando el historial; así la conciliación siempre es confiable.
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.TR_MovimientoInventario_Inmutable
ON dbo.MovimientoInventario
INSTEAD OF UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM deleted) RETURN;   -- la sentencia no afectó filas
    THROW 51006, N'Los movimientos de inventario no se pueden modificar ni eliminar; registre un ajuste.', 1;
END
GO
PRINT '05_triggers.sql: triggers creados.';
GO
