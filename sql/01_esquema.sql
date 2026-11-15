/* =====================================================================
   PROYECTO PROGRAMADO II - BASES DE DATOS
   TiendaTech: comercio electrónico de tecnología
   01_esquema.sql  -  Base de datos, tablas, restricciones e índices
   Motor: Microsoft SQL Server 2019 o superior
   Ejecutar:  sqlcmd -S .\SQLEXPRESS -E -C -f 65001 -i 01_esquema.sql
   ===================================================================== */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;   -- requerido por índices filtrados y columnas calculadas (sqlcmd lo trae en OFF)
GO
USE master;
GO
/* El script es reproducible: recrea la base desde cero. */
IF DB_ID(N'TiendaTechDB') IS NOT NULL
BEGIN
    ALTER DATABASE TiendaTechDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE TiendaTechDB;
END
GO
CREATE DATABASE TiendaTechDB;
GO
USE TiendaTechDB;
GO

/* ---------------------------------------------------------------------
   1. SEGURIDAD: roles, usuarios y clientes
   --------------------------------------------------------------------- */
CREATE TABLE dbo.Rol (
    RolId       TINYINT       NOT NULL,
    Nombre      NVARCHAR(30)  NOT NULL,
    CONSTRAINT PK_Rol PRIMARY KEY (RolId),
    CONSTRAINT UQ_Rol_Nombre UNIQUE (Nombre)
);

CREATE TABLE dbo.Usuario (
    UsuarioId       INT IDENTITY(1,1) NOT NULL,
    Correo          NVARCHAR(120) NOT NULL,
    HashContrasena  NVARCHAR(255) NOT NULL,   -- solo el hash; nunca texto plano
    RolId           TINYINT       NOT NULL,
    Activo          BIT           NOT NULL CONSTRAINT DF_Usuario_Activo DEFAULT (1),
    FechaCreacion   DATETIME2(0)  NOT NULL CONSTRAINT DF_Usuario_Fecha DEFAULT (SYSDATETIME()),
    UltimoAcceso    DATETIME2(0)  NULL,
    CONSTRAINT PK_Usuario PRIMARY KEY (UsuarioId),
    CONSTRAINT UQ_Usuario_Correo UNIQUE (Correo),
    CONSTRAINT FK_Usuario_Rol FOREIGN KEY (RolId) REFERENCES dbo.Rol (RolId),
    CONSTRAINT CK_Usuario_Correo CHECK (Correo LIKE N'_%@_%._%'),
    CONSTRAINT CK_Usuario_Hash CHECK (LEN(HashContrasena) >= 20)
);

CREATE TABLE dbo.Cliente (
    ClienteId       INT IDENTITY(1,1) NOT NULL,
    UsuarioId       INT           NOT NULL,   -- relación 1:1 con Usuario
    Nombre          NVARCHAR(60)  NOT NULL,
    Apellidos       NVARCHAR(80)  NOT NULL,
    Identificacion  VARCHAR(20)   NOT NULL,
    Telefono        VARCHAR(20)   NULL,
    Activo          BIT           NOT NULL CONSTRAINT DF_Cliente_Activo DEFAULT (1),
    FechaRegistro   DATETIME2(0)  NOT NULL CONSTRAINT DF_Cliente_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Cliente PRIMARY KEY (ClienteId),
    CONSTRAINT UQ_Cliente_Usuario UNIQUE (UsuarioId),
    CONSTRAINT UQ_Cliente_Identificacion UNIQUE (Identificacion),
    CONSTRAINT FK_Cliente_Usuario FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuario (UsuarioId),
    CONSTRAINT CK_Cliente_Nombre CHECK (LEN(LTRIM(RTRIM(Nombre))) > 0 AND LEN(LTRIM(RTRIM(Apellidos))) > 0)
);

/* Tabla de zonas: de aquí sale el costo de envío. */
CREATE TABLE dbo.ZonaEnvio (
    ZonaEnvioId     INT IDENTITY(1,1) NOT NULL,
    Nombre          NVARCHAR(60)  NOT NULL,
    Tarifa          DECIMAL(10,2) NOT NULL,
    DiasEstimados   TINYINT       NOT NULL,
    Activo          BIT           NOT NULL CONSTRAINT DF_Zona_Activo DEFAULT (1),
    CONSTRAINT PK_ZonaEnvio PRIMARY KEY (ZonaEnvioId),
    CONSTRAINT UQ_ZonaEnvio_Nombre UNIQUE (Nombre),
    CONSTRAINT CK_ZonaEnvio_Tarifa CHECK (Tarifa >= 0),
    CONSTRAINT CK_ZonaEnvio_Dias CHECK (DiasEstimados BETWEEN 1 AND 30)
);

CREATE TABLE dbo.Direccion (
    DireccionId     INT IDENTITY(1,1) NOT NULL,
    ClienteId       INT           NOT NULL,
    ZonaEnvioId     INT           NOT NULL,
    Alias           NVARCHAR(40)  NOT NULL,
    Provincia       NVARCHAR(40)  NOT NULL,
    Canton          NVARCHAR(60)  NOT NULL,
    Distrito        NVARCHAR(60)  NOT NULL,
    Detalle         NVARCHAR(250) NOT NULL,
    Predeterminada  BIT           NOT NULL CONSTRAINT DF_Direccion_Pred DEFAULT (0),
    Activo          BIT           NOT NULL CONSTRAINT DF_Direccion_Activo DEFAULT (1),
    CONSTRAINT PK_Direccion PRIMARY KEY (DireccionId),
    CONSTRAINT FK_Direccion_Cliente FOREIGN KEY (ClienteId) REFERENCES dbo.Cliente (ClienteId),
    CONSTRAINT FK_Direccion_Zona FOREIGN KEY (ZonaEnvioId) REFERENCES dbo.ZonaEnvio (ZonaEnvioId)
);
/* Regla: como máximo UNA dirección predeterminada activa por cliente. */
CREATE UNIQUE NONCLUSTERED INDEX UX_Direccion_Predeterminada
    ON dbo.Direccion (ClienteId) WHERE Predeterminada = 1 AND Activo = 1;

/* ---------------------------------------------------------------------
   2. CATÁLOGO
   --------------------------------------------------------------------- */
CREATE TABLE dbo.Marca (
    MarcaId     INT IDENTITY(1,1) NOT NULL,
    Nombre      NVARCHAR(60)  NOT NULL,
    PaisOrigen  NVARCHAR(60)  NULL,
    Activo      BIT           NOT NULL CONSTRAINT DF_Marca_Activo DEFAULT (1),
    CONSTRAINT PK_Marca PRIMARY KEY (MarcaId),
    CONSTRAINT UQ_Marca_Nombre UNIQUE (Nombre),
    CONSTRAINT CK_Marca_Nombre CHECK (LEN(LTRIM(RTRIM(Nombre))) > 0)
);

CREATE TABLE dbo.Categoria (
    CategoriaId INT IDENTITY(1,1) NOT NULL,
    Nombre      NVARCHAR(60)  NOT NULL,
    Descripcion NVARCHAR(250) NULL,
    Activo      BIT           NOT NULL CONSTRAINT DF_Categoria_Activo DEFAULT (1),
    CONSTRAINT PK_Categoria PRIMARY KEY (CategoriaId),
    CONSTRAINT UQ_Categoria_Nombre UNIQUE (Nombre),
    CONSTRAINT CK_Categoria_Nombre CHECK (LEN(LTRIM(RTRIM(Nombre))) > 0)
);

CREATE TABLE dbo.Producto (
    ProductoId      INT IDENTITY(1,1) NOT NULL,
    SKU             VARCHAR(20)    NOT NULL,
    Nombre          NVARCHAR(120)  NOT NULL,
    Descripcion     NVARCHAR(500)  NULL,
    Especificaciones NVARCHAR(1000) NULL,
    MarcaId         INT            NOT NULL,
    CategoriaId     INT            NOT NULL,
    Precio          DECIMAL(12,2)  NOT NULL,   -- precio de venta vigente
    Costo           DECIMAL(12,2)  NOT NULL,   -- costo vigente
    Destacado       BIT            NOT NULL CONSTRAINT DF_Producto_Destacado DEFAULT (0),
    Activo          BIT            NOT NULL CONSTRAINT DF_Producto_Activo DEFAULT (1),
    FechaCreacion   DATETIME2(0)   NOT NULL CONSTRAINT DF_Producto_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Producto PRIMARY KEY (ProductoId),
    CONSTRAINT UQ_Producto_SKU UNIQUE (SKU),
    CONSTRAINT FK_Producto_Marca FOREIGN KEY (MarcaId) REFERENCES dbo.Marca (MarcaId),
    CONSTRAINT FK_Producto_Categoria FOREIGN KEY (CategoriaId) REFERENCES dbo.Categoria (CategoriaId),
    CONSTRAINT CK_Producto_Precio CHECK (Precio > 0),
    CONSTRAINT CK_Producto_Costo CHECK (Costo >= 0),
    CONSTRAINT CK_Producto_SKU CHECK (LEN(SKU) >= 3 AND SKU NOT LIKE '% %')
);

CREATE TABLE dbo.ProductoImagen (
    ImagenId    INT IDENTITY(1,1) NOT NULL,
    ProductoId  INT            NOT NULL,
    Url         NVARCHAR(400)  NOT NULL,
    EsPrincipal BIT            NOT NULL CONSTRAINT DF_Imagen_Principal DEFAULT (0),
    Orden       TINYINT        NOT NULL CONSTRAINT DF_Imagen_Orden DEFAULT (1),
    CONSTRAINT PK_ProductoImagen PRIMARY KEY (ImagenId),
    CONSTRAINT FK_Imagen_Producto FOREIGN KEY (ProductoId) REFERENCES dbo.Producto (ProductoId)
);
/* Regla: una sola imagen principal por producto. */
CREATE UNIQUE NONCLUSTERED INDEX UX_ProductoImagen_Principal
    ON dbo.ProductoImagen (ProductoId) WHERE EsPrincipal = 1;

/* ---------------------------------------------------------------------
   3. INVENTARIO
   --------------------------------------------------------------------- */
CREATE TABLE dbo.Inventario (
    ProductoId          INT          NOT NULL,   -- 1:1 con Producto
    Existencia          INT          NOT NULL CONSTRAINT DF_Inventario_Existencia DEFAULT (0),
    StockMinimo         INT          NOT NULL CONSTRAINT DF_Inventario_Minimo DEFAULT (0),
    FechaActualizacion  DATETIME2(0) NOT NULL CONSTRAINT DF_Inventario_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Inventario PRIMARY KEY (ProductoId),
    CONSTRAINT FK_Inventario_Producto FOREIGN KEY (ProductoId) REFERENCES dbo.Producto (ProductoId),
    CONSTRAINT CK_Inventario_Existencia CHECK (Existencia >= 0),   -- nunca existencia negativa
    CONSTRAINT CK_Inventario_Minimo CHECK (StockMinimo >= 0)
);

/* ---------------------------------------------------------------------
   4. CARRITO
   --------------------------------------------------------------------- */
CREATE TABLE dbo.Carrito (
    CarritoId           INT IDENTITY(1,1) NOT NULL,
    ClienteId           INT          NOT NULL,
    FechaCreacion       DATETIME2(0) NOT NULL CONSTRAINT DF_Carrito_Creacion DEFAULT (SYSDATETIME()),
    FechaActualizacion  DATETIME2(0) NOT NULL CONSTRAINT DF_Carrito_Actualizacion DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Carrito PRIMARY KEY (CarritoId),
    CONSTRAINT UQ_Carrito_Cliente UNIQUE (ClienteId),   -- un carrito persistente por cliente
    CONSTRAINT FK_Carrito_Cliente FOREIGN KEY (ClienteId) REFERENCES dbo.Cliente (ClienteId)
);

CREATE TABLE dbo.DetalleCarrito (
    CarritoId       INT          NOT NULL,
    ProductoId      INT          NOT NULL,
    Cantidad        INT          NOT NULL,
    FechaAgregado   DATETIME2(0) NOT NULL CONSTRAINT DF_DetCarrito_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_DetalleCarrito PRIMARY KEY (CarritoId, ProductoId),   -- sin líneas duplicadas
    CONSTRAINT FK_DetCarrito_Carrito FOREIGN KEY (CarritoId) REFERENCES dbo.Carrito (CarritoId),
    CONSTRAINT FK_DetCarrito_Producto FOREIGN KEY (ProductoId) REFERENCES dbo.Producto (ProductoId),
    CONSTRAINT CK_DetCarrito_Cantidad CHECK (Cantidad > 0)
);

/* ---------------------------------------------------------------------
   5. PROMOCIONES
   --------------------------------------------------------------------- */
CREATE TABLE dbo.Promocion (
    PromocionId     INT IDENTITY(1,1) NOT NULL,
    Nombre          NVARCHAR(80)  NOT NULL,
    TipoDescuento   CHAR(1)       NOT NULL,   -- P = porcentaje, M = monto fijo
    Valor           DECIMAL(12,2) NOT NULL,
    FechaInicio     DATE          NOT NULL,
    FechaFin        DATE          NOT NULL,
    Activo          BIT           NOT NULL CONSTRAINT DF_Promocion_Activo DEFAULT (1),
    CONSTRAINT PK_Promocion PRIMARY KEY (PromocionId),
    CONSTRAINT UQ_Promocion_Nombre UNIQUE (Nombre),
    CONSTRAINT CK_Promocion_Tipo CHECK (TipoDescuento IN ('P','M')),
    CONSTRAINT CK_Promocion_Valor CHECK (Valor > 0 AND (TipoDescuento = 'M' OR Valor <= 100)),
    CONSTRAINT CK_Promocion_Fechas CHECK (FechaFin >= FechaInicio)
);

/* Relación N:M entre promociones y productos. */
CREATE TABLE dbo.PromocionProducto (
    PromocionId INT NOT NULL,
    ProductoId  INT NOT NULL,
    CONSTRAINT PK_PromocionProducto PRIMARY KEY (PromocionId, ProductoId),
    CONSTRAINT FK_PromProd_Promocion FOREIGN KEY (PromocionId) REFERENCES dbo.Promocion (PromocionId),
    CONSTRAINT FK_PromProd_Producto FOREIGN KEY (ProductoId) REFERENCES dbo.Producto (ProductoId)
);

/* ---------------------------------------------------------------------
   6. PEDIDOS, PAGOS Y ENVÍOS
   --------------------------------------------------------------------- */
CREATE TABLE dbo.EstadoPedido (
    EstadoId    TINYINT       NOT NULL,
    Nombre      NVARCHAR(30)  NOT NULL,
    EsFinal     BIT           NOT NULL CONSTRAINT DF_Estado_EsFinal DEFAULT (0),
    CONSTRAINT PK_EstadoPedido PRIMARY KEY (EstadoId),
    CONSTRAINT UQ_EstadoPedido_Nombre UNIQUE (Nombre)
);

/* Las transiciones válidas son DATOS, no código: se consultan en los procedimientos. */
CREATE TABLE dbo.TransicionEstado (
    EstadoOrigenId  TINYINT NOT NULL,
    EstadoDestinoId TINYINT NOT NULL,
    CONSTRAINT PK_TransicionEstado PRIMARY KEY (EstadoOrigenId, EstadoDestinoId),
    CONSTRAINT FK_Transicion_Origen FOREIGN KEY (EstadoOrigenId) REFERENCES dbo.EstadoPedido (EstadoId),
    CONSTRAINT FK_Transicion_Destino FOREIGN KEY (EstadoDestinoId) REFERENCES dbo.EstadoPedido (EstadoId),
    CONSTRAINT CK_Transicion_Distintos CHECK (EstadoOrigenId <> EstadoDestinoId)
);

CREATE TABLE dbo.MetodoPago (
    MetodoPagoId        INT IDENTITY(1,1) NOT NULL,
    Nombre              NVARCHAR(40) NOT NULL,
    AprobacionInmediata BIT          NOT NULL,   -- 1: el pago simulado se aprueba en el checkout
    Activo              BIT          NOT NULL CONSTRAINT DF_MetodoPago_Activo DEFAULT (1),
    CONSTRAINT PK_MetodoPago PRIMARY KEY (MetodoPagoId),
    CONSTRAINT UQ_MetodoPago_Nombre UNIQUE (Nombre)
);

CREATE TABLE dbo.Pedido (
    PedidoId        INT IDENTITY(1,1) NOT NULL,
    ClienteId       INT           NOT NULL,
    DireccionId     INT           NOT NULL,
    EstadoId        TINYINT       NOT NULL CONSTRAINT DF_Pedido_Estado DEFAULT (1),
    FechaPedido     DATETIME2(0)  NOT NULL CONSTRAINT DF_Pedido_Fecha DEFAULT (SYSDATETIME()),
    /* Importes históricos del pedido (desnormalización justificada, ver documento):
       se congelan al confirmar y no cambian aunque cambie el catálogo. */
    Subtotal        DECIMAL(14,2) NOT NULL,
    DescuentoTotal  DECIMAL(14,2) NOT NULL CONSTRAINT DF_Pedido_Descuento DEFAULT (0),
    CostoEnvio      DECIMAL(10,2) NOT NULL CONSTRAINT DF_Pedido_Envio DEFAULT (0),
    Total AS (CONVERT(DECIMAL(14,2), Subtotal - DescuentoTotal + CostoEnvio)) PERSISTED,
    CONSTRAINT PK_Pedido PRIMARY KEY (PedidoId),
    CONSTRAINT FK_Pedido_Cliente FOREIGN KEY (ClienteId) REFERENCES dbo.Cliente (ClienteId),
    CONSTRAINT FK_Pedido_Direccion FOREIGN KEY (DireccionId) REFERENCES dbo.Direccion (DireccionId),
    CONSTRAINT FK_Pedido_Estado FOREIGN KEY (EstadoId) REFERENCES dbo.EstadoPedido (EstadoId),
    CONSTRAINT CK_Pedido_Importes CHECK (Subtotal >= 0 AND DescuentoTotal >= 0
                                         AND DescuentoTotal <= Subtotal AND CostoEnvio >= 0)
);

CREATE TABLE dbo.DetallePedido (
    PedidoId            INT           NOT NULL,
    ProductoId          INT           NOT NULL,
    Cantidad            INT           NOT NULL,
    PrecioUnitario      DECIMAL(12,2) NOT NULL,   -- precio histórico al momento de la compra
    DescuentoUnitario   DECIMAL(12,2) NOT NULL CONSTRAINT DF_DetPedido_Desc DEFAULT (0),
    CostoUnitario       DECIMAL(12,2) NOT NULL,   -- costo histórico (para rentabilidad)
    PromocionId         INT           NULL,       -- promoción aplicada, si hubo
    TotalLinea AS (CONVERT(DECIMAL(14,2), Cantidad * (PrecioUnitario - DescuentoUnitario))) PERSISTED,
    CONSTRAINT PK_DetallePedido PRIMARY KEY (PedidoId, ProductoId),   -- sin líneas duplicadas
    CONSTRAINT FK_DetPedido_Pedido FOREIGN KEY (PedidoId) REFERENCES dbo.Pedido (PedidoId),
    CONSTRAINT FK_DetPedido_Producto FOREIGN KEY (ProductoId) REFERENCES dbo.Producto (ProductoId),
    CONSTRAINT FK_DetPedido_Promocion FOREIGN KEY (PromocionId) REFERENCES dbo.Promocion (PromocionId),
    CONSTRAINT CK_DetPedido_Cantidad CHECK (Cantidad > 0),
    CONSTRAINT CK_DetPedido_Precio CHECK (PrecioUnitario > 0 AND CostoUnitario >= 0),
    CONSTRAINT CK_DetPedido_Descuento CHECK (DescuentoUnitario >= 0 AND DescuentoUnitario <= PrecioUnitario)
);

/* Historial de estados: lo llena el trigger TR_Pedido_HistorialEstado (05_triggers.sql). */
CREATE TABLE dbo.HistorialEstadoPedido (
    HistorialId         INT IDENTITY(1,1) NOT NULL,
    PedidoId            INT           NOT NULL,
    EstadoAnteriorId    TINYINT       NULL,      -- NULL en la creación del pedido
    EstadoNuevoId       TINYINT       NOT NULL,
    Fecha               DATETIME2(3)  NOT NULL CONSTRAINT DF_Historial_Fecha DEFAULT (SYSDATETIME()),
    UsuarioId           INT           NULL,      -- usuario de la aplicación
    UsuarioBD           SYSNAME       NOT NULL CONSTRAINT DF_Historial_UsuarioBD DEFAULT (ORIGINAL_LOGIN()),
    Comentario          NVARCHAR(250) NULL,
    CONSTRAINT PK_HistorialEstadoPedido PRIMARY KEY (HistorialId),
    CONSTRAINT FK_Historial_Pedido FOREIGN KEY (PedidoId) REFERENCES dbo.Pedido (PedidoId),
    CONSTRAINT FK_Historial_EstadoAnt FOREIGN KEY (EstadoAnteriorId) REFERENCES dbo.EstadoPedido (EstadoId),
    CONSTRAINT FK_Historial_EstadoNuevo FOREIGN KEY (EstadoNuevoId) REFERENCES dbo.EstadoPedido (EstadoId),
    CONSTRAINT FK_Historial_Usuario FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuario (UsuarioId)
);

CREATE TABLE dbo.Pago (
    PagoId          INT IDENTITY(1,1) NOT NULL,
    PedidoId        INT           NOT NULL,
    MetodoPagoId    INT           NOT NULL,
    Monto           DECIMAL(14,2) NOT NULL,
    Estado          VARCHAR(12)   NOT NULL,
    Referencia      VARCHAR(40)   NOT NULL,     -- comprobante simulado
    Fecha           DATETIME2(0)  NOT NULL CONSTRAINT DF_Pago_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Pago PRIMARY KEY (PagoId),
    CONSTRAINT UQ_Pago_Pedido UNIQUE (PedidoId),          -- un pago simulado por pedido
    CONSTRAINT UQ_Pago_Referencia UNIQUE (Referencia),
    CONSTRAINT FK_Pago_Pedido FOREIGN KEY (PedidoId) REFERENCES dbo.Pedido (PedidoId),
    CONSTRAINT FK_Pago_Metodo FOREIGN KEY (MetodoPagoId) REFERENCES dbo.MetodoPago (MetodoPagoId),
    CONSTRAINT CK_Pago_Monto CHECK (Monto > 0),
    CONSTRAINT CK_Pago_Estado CHECK (Estado IN ('PENDIENTE','APROBADO','REEMBOLSADO','ANULADO'))
);

CREATE TABLE dbo.Envio (
    EnvioId         INT IDENTITY(1,1) NOT NULL,
    PedidoId        INT           NOT NULL,
    ZonaEnvioId     INT           NOT NULL,
    NumeroGuia      VARCHAR(30)   NULL,        -- se asigna al despachar
    FechaDespacho   DATETIME2(0)  NULL,
    FechaEntrega    DATETIME2(0)  NULL,
    CONSTRAINT PK_Envio PRIMARY KEY (EnvioId),
    CONSTRAINT UQ_Envio_Pedido UNIQUE (PedidoId),
    CONSTRAINT FK_Envio_Pedido FOREIGN KEY (PedidoId) REFERENCES dbo.Pedido (PedidoId),
    CONSTRAINT FK_Envio_Zona FOREIGN KEY (ZonaEnvioId) REFERENCES dbo.ZonaEnvio (ZonaEnvioId),
    CONSTRAINT CK_Envio_Fechas CHECK (FechaEntrega IS NULL OR (FechaDespacho IS NOT NULL AND FechaEntrega >= FechaDespacho))
);
CREATE UNIQUE NONCLUSTERED INDEX UX_Envio_NumeroGuia
    ON dbo.Envio (NumeroGuia) WHERE NumeroGuia IS NOT NULL;

/* Libro de movimientos de inventario. Cantidad lleva signo:
   ENTRADA > 0, SALIDA < 0, AJUSTE distinto de 0.
   Así SUM(Cantidad) por producto debe ser igual a Inventario.Existencia. */
CREATE TABLE dbo.MovimientoInventario (
    MovimientoId        INT IDENTITY(1,1) NOT NULL,
    ProductoId          INT           NOT NULL,
    Tipo                VARCHAR(10)   NOT NULL,
    Cantidad            INT           NOT NULL,
    ExistenciaResultante INT          NOT NULL,
    Fecha               DATETIME2(0)  NOT NULL CONSTRAINT DF_Movimiento_Fecha DEFAULT (SYSDATETIME()),
    UsuarioId           INT           NOT NULL,
    Motivo              NVARCHAR(200) NOT NULL,
    PedidoId            INT           NULL,     -- pedido que originó el movimiento
    CONSTRAINT PK_MovimientoInventario PRIMARY KEY (MovimientoId),
    CONSTRAINT FK_Movimiento_Producto FOREIGN KEY (ProductoId) REFERENCES dbo.Producto (ProductoId),
    CONSTRAINT FK_Movimiento_Usuario FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuario (UsuarioId),
    CONSTRAINT FK_Movimiento_Pedido FOREIGN KEY (PedidoId) REFERENCES dbo.Pedido (PedidoId),
    CONSTRAINT CK_Movimiento_Tipo CHECK (Tipo IN ('ENTRADA','SALIDA','AJUSTE')),
    CONSTRAINT CK_Movimiento_Signo CHECK ((Tipo = 'ENTRADA' AND Cantidad > 0)
                                       OR (Tipo = 'SALIDA'  AND Cantidad < 0)
                                       OR (Tipo = 'AJUSTE'  AND Cantidad <> 0)),
    CONSTRAINT CK_Movimiento_Resultante CHECK (ExistenciaResultante >= 0),
    CONSTRAINT CK_Movimiento_Motivo CHECK (LEN(LTRIM(RTRIM(Motivo))) > 0)
);

/* ---------------------------------------------------------------------
   7. RESEÑAS Y AUDITORÍA
   --------------------------------------------------------------------- */
CREATE TABLE dbo.Resena (
    ResenaId        INT IDENTITY(1,1) NOT NULL,
    ClienteId       INT           NOT NULL,
    ProductoId      INT           NOT NULL,
    Calificacion    TINYINT       NOT NULL,
    Comentario      NVARCHAR(500) NULL,
    Fecha           DATETIME2(0)  NOT NULL CONSTRAINT DF_Resena_Fecha DEFAULT (SYSDATETIME()),
    Activo          BIT           NOT NULL CONSTRAINT DF_Resena_Activo DEFAULT (1),
    CONSTRAINT PK_Resena PRIMARY KEY (ResenaId),
    CONSTRAINT UQ_Resena_Cliente_Producto UNIQUE (ClienteId, ProductoId),   -- una reseña por cliente y producto
    CONSTRAINT FK_Resena_Cliente FOREIGN KEY (ClienteId) REFERENCES dbo.Cliente (ClienteId),
    CONSTRAINT FK_Resena_Producto FOREIGN KEY (ProductoId) REFERENCES dbo.Producto (ProductoId),
    CONSTRAINT CK_Resena_Calificacion CHECK (Calificacion BETWEEN 1 AND 5)
);

/* Auditoría de precios: la llena el trigger TR_Producto_AuditoriaPrecio (05_triggers.sql). */
CREATE TABLE dbo.AuditoriaPrecio (
    AuditoriaId     INT IDENTITY(1,1) NOT NULL,
    ProductoId      INT           NOT NULL,
    PrecioAnterior  DECIMAL(12,2) NOT NULL,
    PrecioNuevo     DECIMAL(12,2) NOT NULL,
    Fecha           DATETIME2(3)  NOT NULL CONSTRAINT DF_AudPrecio_Fecha DEFAULT (SYSDATETIME()),
    UsuarioId       INT           NULL,
    UsuarioBD       SYSNAME       NOT NULL CONSTRAINT DF_AudPrecio_UsuarioBD DEFAULT (ORIGINAL_LOGIN()),
    CONSTRAINT PK_AuditoriaPrecio PRIMARY KEY (AuditoriaId),
    CONSTRAINT FK_AudPrecio_Producto FOREIGN KEY (ProductoId) REFERENCES dbo.Producto (ProductoId),
    CONSTRAINT FK_AudPrecio_Usuario FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuario (UsuarioId)
);
GO

/* ---------------------------------------------------------------------
   8. ÍNDICES NO AGRUPADOS (justificación en docs/ y evidencia en
      08_evidencia_indices.sql)
   --------------------------------------------------------------------- */
-- IX1. Catálogo filtrado por categoría (pantalla principal de la tienda).
CREATE NONCLUSTERED INDEX IX_Producto_Categoria
    ON dbo.Producto (CategoriaId, Activo) INCLUDE (Nombre, Precio, MarcaId, SKU);
-- IX2. Catálogo filtrado por marca y reportes por marca.
CREATE NONCLUSTERED INDEX IX_Producto_Marca
    ON dbo.Producto (MarcaId, Activo) INCLUDE (Nombre, Precio, CategoriaId, SKU);
-- IX3. Historial de pedidos de un cliente, del más reciente al más antiguo.
CREATE NONCLUSTERED INDEX IX_Pedido_Cliente_Fecha
    ON dbo.Pedido (ClienteId, FechaPedido DESC) INCLUDE (EstadoId, Subtotal, DescuentoTotal, CostoEnvio);
-- IX4. Reportes por rango de fechas (R3, R4, R9, R10).
CREATE NONCLUSTERED INDEX IX_Pedido_Fecha
    ON dbo.Pedido (FechaPedido) INCLUDE (EstadoId, ClienteId);
-- IX5. Ventas por producto (R5, R7): la PK empieza por PedidoId y no sirve para buscar por producto.
CREATE NONCLUSTERED INDEX IX_DetallePedido_Producto
    ON dbo.DetallePedido (ProductoId) INCLUDE (Cantidad, PrecioUnitario, DescuentoUnitario, CostoUnitario);
-- IX6. Kardex de un producto y conciliación de inventario.
CREATE NONCLUSTERED INDEX IX_Movimiento_Producto_Fecha
    ON dbo.MovimientoInventario (ProductoId, Fecha) INCLUDE (Tipo, Cantidad);
-- IX7. Reseñas y calificación promedio de un producto.
CREATE NONCLUSTERED INDEX IX_Resena_Producto
    ON dbo.Resena (ProductoId, Activo) INCLUDE (Calificacion);
-- IX8. Promociones que aplican a un producto (la PK empieza por PromocionId).
CREATE NONCLUSTERED INDEX IX_PromocionProducto_Producto
    ON dbo.PromocionProducto (ProductoId);
GO
PRINT '01_esquema.sql: base TiendaTechDB creada correctamente.';
GO
