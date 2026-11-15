/* =====================================================================
   03_procedimientos.sql  -  Función y procedimientos almacenados
   Convenciones:
     - Nombre: usp_<Entidad>_<Acción>.
     - Toda validación de negocio se hace aquí (no solo en la interfaz).
     - Errores de negocio: THROW con número 51000-51099 y mensaje legible.
         51000 dato inválido          51004 transición de estado inválida
         51001 no existe              51005 carrito vacío
         51002 duplicado              51006 operación no permitida
         51003 existencia insuficiente 51007 registro referenciado
     - Procedimientos transaccionales: BEGIN TRY / BEGIN TRAN / COMMIT,
       y en el CATCH: ROLLBACK + THROW.
     - El usuario de la aplicación viaja como parámetro y se guarda en
       SESSION_CONTEXT para que los triggers de auditoría lo registren.
   ===================================================================== */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE TiendaTechDB;
GO

/* =====================================================================
   FUNCIÓN: mejor promoción vigente de un producto en una fecha.
   Regla de combinación: las promociones NO se acumulan; si un producto
   está en varias promociones vigentes se aplica solo la de mayor descuento.
   El descuento nunca supera el precio (no hay importes negativos).
   ===================================================================== */
CREATE OR ALTER FUNCTION dbo.fn_MejorPromocion (@ProductoId INT, @Fecha DATE)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (1) m.PromocionId, m.Nombre AS Promocion, x.Descuento
    FROM dbo.PromocionProducto pp
    JOIN dbo.Promocion m ON m.PromocionId = pp.PromocionId
    JOIN dbo.Producto p ON p.ProductoId = pp.ProductoId
    CROSS APPLY (SELECT CAST(CASE WHEN m.TipoDescuento = 'P' THEN ROUND(p.Precio * m.Valor / 100.0, 2)
                                  WHEN m.Valor > p.Precio THEN p.Precio
                                  ELSE m.Valor END AS DECIMAL(12,2)) AS Descuento) x
    WHERE pp.ProductoId = @ProductoId
      AND m.Activo = 1
      AND @Fecha BETWEEN m.FechaInicio AND m.FechaFin
    ORDER BY x.Descuento DESC, m.PromocionId
);
GO

/* =====================================================================
   USUARIOS Y CLIENTES
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_Usuario_ObtenerPorCorreo
    @Correo NVARCHAR(120)
AS
BEGIN
    SET NOCOUNT ON;
    /* La aplicación verifica el hash; la contraseña nunca llega a SQL Server. */
    SELECT u.UsuarioId, u.Correo, u.HashContrasena, u.RolId, r.Nombre AS Rol, u.Activo,
           c.ClienteId, ISNULL(c.Nombre + N' ' + c.Apellidos, N'Administrador') AS NombreCompleto
    FROM dbo.Usuario u
    JOIN dbo.Rol r ON r.RolId = u.RolId
    LEFT JOIN dbo.Cliente c ON c.UsuarioId = u.UsuarioId
    WHERE u.Correo = LTRIM(RTRIM(@Correo));
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Usuario_RegistrarAcceso
    @UsuarioId INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.Usuario SET UltimoAcceso = SYSDATETIME() WHERE UsuarioId = @UsuarioId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Usuario_CambiarContrasena
    @UsuarioId INT,
    @HashNuevo NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    IF @HashNuevo IS NULL OR LEN(@HashNuevo) < 20
        THROW 51000, N'El hash de la contraseña no es válido.', 1;
    UPDATE dbo.Usuario SET HashContrasena = @HashNuevo WHERE UsuarioId = @UsuarioId;
    IF @@ROWCOUNT = 0 THROW 51001, N'El usuario no existe.', 1;
END
GO

/* Crea usuario + cliente + carrito en una sola transacción. Devuelve el Id por OUTPUT. */
CREATE OR ALTER PROCEDURE dbo.usp_Cliente_Registrar
    @Correo         NVARCHAR(120),
    @HashContrasena NVARCHAR(255),
    @Nombre         NVARCHAR(60),
    @Apellidos      NVARCHAR(80),
    @Identificacion VARCHAR(20),
    @Telefono       VARCHAR(20) = NULL,
    @ClienteId      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SELECT @Correo = LOWER(LTRIM(RTRIM(@Correo))), @Nombre = LTRIM(RTRIM(@Nombre)),
           @Apellidos = LTRIM(RTRIM(@Apellidos)), @Identificacion = LTRIM(RTRIM(@Identificacion)),
           @Telefono = NULLIF(LTRIM(RTRIM(@Telefono)), '');

    IF @Correo IS NULL OR @Correo NOT LIKE N'_%@_%._%'
        THROW 51000, N'El correo electrónico no tiene un formato válido.', 1;
    IF ISNULL(@Nombre, N'') = N'' OR ISNULL(@Apellidos, N'') = N''
        THROW 51000, N'El nombre y los apellidos son obligatorios.', 1;
    IF ISNULL(@Identificacion, '') = ''
        THROW 51000, N'La identificación es obligatoria.', 1;
    IF @HashContrasena IS NULL OR LEN(@HashContrasena) < 20
        THROW 51000, N'El hash de la contraseña no es válido.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        IF EXISTS (SELECT 1 FROM dbo.Usuario WITH (UPDLOCK, HOLDLOCK) WHERE Correo = @Correo)
            THROW 51002, N'Ya existe una cuenta registrada con ese correo.', 1;
        IF EXISTS (SELECT 1 FROM dbo.Cliente WITH (UPDLOCK, HOLDLOCK) WHERE Identificacion = @Identificacion)
            THROW 51002, N'Ya existe un cliente con esa identificación.', 1;

        INSERT INTO dbo.Usuario (Correo, HashContrasena, RolId) VALUES (@Correo, @HashContrasena, 2);
        DECLARE @UsuarioId INT = SCOPE_IDENTITY();

        INSERT INTO dbo.Cliente (UsuarioId, Nombre, Apellidos, Identificacion, Telefono)
        VALUES (@UsuarioId, @Nombre, @Apellidos, @Identificacion, @Telefono);
        SET @ClienteId = SCOPE_IDENTITY();

        INSERT INTO dbo.Carrito (ClienteId) VALUES (@ClienteId);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Cliente_Actualizar
    @ClienteId      INT,
    @Nombre         NVARCHAR(60),
    @Apellidos      NVARCHAR(80),
    @Identificacion VARCHAR(20),
    @Telefono       VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @Nombre = LTRIM(RTRIM(@Nombre)), @Apellidos = LTRIM(RTRIM(@Apellidos)),
           @Identificacion = LTRIM(RTRIM(@Identificacion)), @Telefono = NULLIF(LTRIM(RTRIM(@Telefono)), '');
    IF ISNULL(@Nombre, N'') = N'' OR ISNULL(@Apellidos, N'') = N'' OR ISNULL(@Identificacion, '') = ''
        THROW 51000, N'Nombre, apellidos e identificación son obligatorios.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Cliente WHERE Identificacion = @Identificacion AND ClienteId <> @ClienteId)
        THROW 51002, N'Ya existe otro cliente con esa identificación.', 1;

    UPDATE dbo.Cliente
    SET Nombre = @Nombre, Apellidos = @Apellidos, Identificacion = @Identificacion, Telefono = @Telefono
    WHERE ClienteId = @ClienteId;
    IF @@ROWCOUNT = 0 THROW 51001, N'El cliente no existe.', 1;
END
GO

/* Eliminación lógica: un cliente con historial nunca se borra, se desactiva (y su acceso también). */
CREATE OR ALTER PROCEDURE dbo.usp_Cliente_CambiarEstado
    @ClienteId INT,
    @Activo    BIT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE dbo.Cliente SET Activo = @Activo WHERE ClienteId = @ClienteId;
        IF @@ROWCOUNT = 0 THROW 51001, N'El cliente no existe.', 1;
        UPDATE u SET Activo = @Activo
        FROM dbo.Usuario u JOIN dbo.Cliente c ON c.UsuarioId = u.UsuarioId
        WHERE c.ClienteId = @ClienteId;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Cliente_Listar
    @Buscar NVARCHAR(100) = NULL,
    @Activo BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Buscar = NULLIF(LTRIM(RTRIM(@Buscar)), N'');
    SELECT c.ClienteId, c.Nombre, c.Apellidos, c.Identificacion, c.Telefono, u.Correo, c.Activo, c.FechaRegistro,
           (SELECT COUNT(*) FROM dbo.Pedido o WHERE o.ClienteId = c.ClienteId) AS Pedidos
    FROM dbo.Cliente c
    JOIN dbo.Usuario u ON u.UsuarioId = c.UsuarioId
    WHERE (@Activo IS NULL OR c.Activo = @Activo)
      AND (@Buscar IS NULL
           OR c.Nombre + N' ' + c.Apellidos LIKE N'%' + @Buscar + N'%'
           OR u.Correo LIKE N'%' + @Buscar + N'%'
           OR c.Identificacion LIKE N'%' + @Buscar + N'%')
    ORDER BY c.Apellidos, c.Nombre;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Cliente_Obtener
    @ClienteId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.ClienteId, c.UsuarioId, c.Nombre, c.Apellidos, c.Identificacion, c.Telefono, u.Correo, c.Activo, c.FechaRegistro
    FROM dbo.Cliente c JOIN dbo.Usuario u ON u.UsuarioId = c.UsuarioId
    WHERE c.ClienteId = @ClienteId;
END
GO

/* ---------------- Direcciones y zonas ---------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ZonaEnvio_Listar
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ZonaEnvioId, Nombre, Tarifa, DiasEstimados FROM dbo.ZonaEnvio WHERE Activo = 1 ORDER BY ZonaEnvioId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Direccion_Crear
    @ClienteId      INT,
    @ZonaEnvioId    INT,
    @Alias          NVARCHAR(40),
    @Provincia      NVARCHAR(40),
    @Canton         NVARCHAR(60),
    @Distrito       NVARCHAR(60),
    @Detalle        NVARCHAR(250),
    @Predeterminada BIT = 0,
    @DireccionId    INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF ISNULL(LTRIM(RTRIM(@Alias)), N'') = N'' OR ISNULL(LTRIM(RTRIM(@Provincia)), N'') = N''
       OR ISNULL(LTRIM(RTRIM(@Canton)), N'') = N'' OR ISNULL(LTRIM(RTRIM(@Distrito)), N'') = N''
       OR ISNULL(LTRIM(RTRIM(@Detalle)), N'') = N''
        THROW 51000, N'Todos los campos de la dirección son obligatorios.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Cliente WHERE ClienteId = @ClienteId)
        THROW 51001, N'El cliente no existe.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.ZonaEnvio WHERE ZonaEnvioId = @ZonaEnvioId AND Activo = 1)
        THROW 51001, N'La zona de envío no existe.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        /* La primera dirección del cliente siempre queda como predeterminada. */
        IF NOT EXISTS (SELECT 1 FROM dbo.Direccion WITH (UPDLOCK, HOLDLOCK) WHERE ClienteId = @ClienteId AND Activo = 1)
            SET @Predeterminada = 1;
        IF @Predeterminada = 1
            UPDATE dbo.Direccion SET Predeterminada = 0 WHERE ClienteId = @ClienteId AND Predeterminada = 1;

        INSERT INTO dbo.Direccion (ClienteId, ZonaEnvioId, Alias, Provincia, Canton, Distrito, Detalle, Predeterminada)
        VALUES (@ClienteId, @ZonaEnvioId, LTRIM(RTRIM(@Alias)), LTRIM(RTRIM(@Provincia)), LTRIM(RTRIM(@Canton)),
                LTRIM(RTRIM(@Distrito)), LTRIM(RTRIM(@Detalle)), @Predeterminada);
        SET @DireccionId = SCOPE_IDENTITY();
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Direccion_Actualizar
    @DireccionId    INT,
    @ClienteId      INT,
    @ZonaEnvioId    INT,
    @Alias          NVARCHAR(40),
    @Provincia      NVARCHAR(40),
    @Canton         NVARCHAR(60),
    @Distrito       NVARCHAR(60),
    @Detalle        NVARCHAR(250),
    @Predeterminada BIT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF ISNULL(LTRIM(RTRIM(@Alias)), N'') = N'' OR ISNULL(LTRIM(RTRIM(@Provincia)), N'') = N''
       OR ISNULL(LTRIM(RTRIM(@Canton)), N'') = N'' OR ISNULL(LTRIM(RTRIM(@Distrito)), N'') = N''
       OR ISNULL(LTRIM(RTRIM(@Detalle)), N'') = N''
        THROW 51000, N'Todos los campos de la dirección son obligatorios.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Direccion WHERE DireccionId = @DireccionId AND ClienteId = @ClienteId AND Activo = 1)
        THROW 51001, N'La dirección no existe o no pertenece al cliente.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.ZonaEnvio WHERE ZonaEnvioId = @ZonaEnvioId AND Activo = 1)
        THROW 51001, N'La zona de envío no existe.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        IF @Predeterminada = 1
            UPDATE dbo.Direccion SET Predeterminada = 0
            WHERE ClienteId = @ClienteId AND Predeterminada = 1 AND DireccionId <> @DireccionId;
        UPDATE dbo.Direccion
        SET ZonaEnvioId = @ZonaEnvioId, Alias = LTRIM(RTRIM(@Alias)), Provincia = LTRIM(RTRIM(@Provincia)),
            Canton = LTRIM(RTRIM(@Canton)), Distrito = LTRIM(RTRIM(@Distrito)), Detalle = LTRIM(RTRIM(@Detalle)),
            Predeterminada = CASE WHEN @Predeterminada = 1 THEN 1 ELSE Predeterminada END
        WHERE DireccionId = @DireccionId;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* Eliminación lógica: los pedidos anteriores siguen apuntando a la dirección. */
CREATE OR ALTER PROCEDURE dbo.usp_Direccion_Eliminar
    @DireccionId INT,
    @ClienteId   INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.Direccion SET Activo = 0, Predeterminada = 0
    WHERE DireccionId = @DireccionId AND ClienteId = @ClienteId AND Activo = 1;
    IF @@ROWCOUNT = 0 THROW 51001, N'La dirección no existe o no pertenece al cliente.', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Direccion_ListarPorCliente
    @ClienteId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.DireccionId, d.Alias, d.Provincia, d.Canton, d.Distrito, d.Detalle, d.Predeterminada,
           d.ZonaEnvioId, z.Nombre AS Zona, z.Tarifa, z.DiasEstimados
    FROM dbo.Direccion d JOIN dbo.ZonaEnvio z ON z.ZonaEnvioId = d.ZonaEnvioId
    WHERE d.ClienteId = @ClienteId AND d.Activo = 1
    ORDER BY d.Predeterminada DESC, d.Alias;
END
GO

/* =====================================================================
   MARCAS Y CATEGORÍAS
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_Marca_Crear
    @Nombre     NVARCHAR(60),
    @PaisOrigen NVARCHAR(60) = NULL,
    @MarcaId    INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Nombre = LTRIM(RTRIM(@Nombre));
    IF ISNULL(@Nombre, N'') = N'' THROW 51000, N'El nombre de la marca es obligatorio.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Marca WHERE Nombre = @Nombre)
        THROW 51002, N'Ya existe una marca con ese nombre.', 1;
    INSERT INTO dbo.Marca (Nombre, PaisOrigen) VALUES (@Nombre, NULLIF(LTRIM(RTRIM(@PaisOrigen)), N''));
    SET @MarcaId = SCOPE_IDENTITY();
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Marca_Actualizar
    @MarcaId    INT,
    @Nombre     NVARCHAR(60),
    @PaisOrigen NVARCHAR(60) = NULL,
    @Activo     BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET @Nombre = LTRIM(RTRIM(@Nombre));
    IF ISNULL(@Nombre, N'') = N'' THROW 51000, N'El nombre de la marca es obligatorio.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Marca WHERE Nombre = @Nombre AND MarcaId <> @MarcaId)
        THROW 51002, N'Ya existe otra marca con ese nombre.', 1;
    UPDATE dbo.Marca SET Nombre = @Nombre, PaisOrigen = NULLIF(LTRIM(RTRIM(@PaisOrigen)), N''), Activo = @Activo
    WHERE MarcaId = @MarcaId;
    IF @@ROWCOUNT = 0 THROW 51001, N'La marca no existe.', 1;
END
GO

/* Eliminación física solo si nada la referencia; de lo contrario se debe desactivar. */
CREATE OR ALTER PROCEDURE dbo.usp_Marca_Eliminar
    @MarcaId INT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM dbo.Producto WHERE MarcaId = @MarcaId)
        THROW 51007, N'La marca tiene productos asociados: no se puede eliminar, solo desactivar.', 1;
    DELETE FROM dbo.Marca WHERE MarcaId = @MarcaId;
    IF @@ROWCOUNT = 0 THROW 51001, N'La marca no existe.', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Marca_Listar
    @Buscar NVARCHAR(60) = NULL,
    @Activo BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Buscar = NULLIF(LTRIM(RTRIM(@Buscar)), N'');
    SELECT m.MarcaId, m.Nombre, m.PaisOrigen, m.Activo,
           (SELECT COUNT(*) FROM dbo.Producto p WHERE p.MarcaId = m.MarcaId) AS Productos
    FROM dbo.Marca m
    WHERE (@Activo IS NULL OR m.Activo = @Activo)
      AND (@Buscar IS NULL OR m.Nombre LIKE N'%' + @Buscar + N'%')
    ORDER BY m.Nombre;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Categoria_Crear
    @Nombre      NVARCHAR(60),
    @Descripcion NVARCHAR(250) = NULL,
    @CategoriaId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Nombre = LTRIM(RTRIM(@Nombre));
    IF ISNULL(@Nombre, N'') = N'' THROW 51000, N'El nombre de la categoría es obligatorio.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Categoria WHERE Nombre = @Nombre)
        THROW 51002, N'Ya existe una categoría con ese nombre.', 1;
    INSERT INTO dbo.Categoria (Nombre, Descripcion) VALUES (@Nombre, NULLIF(LTRIM(RTRIM(@Descripcion)), N''));
    SET @CategoriaId = SCOPE_IDENTITY();
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Categoria_Actualizar
    @CategoriaId INT,
    @Nombre      NVARCHAR(60),
    @Descripcion NVARCHAR(250) = NULL,
    @Activo      BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET @Nombre = LTRIM(RTRIM(@Nombre));
    IF ISNULL(@Nombre, N'') = N'' THROW 51000, N'El nombre de la categoría es obligatorio.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Categoria WHERE Nombre = @Nombre AND CategoriaId <> @CategoriaId)
        THROW 51002, N'Ya existe otra categoría con ese nombre.', 1;
    UPDATE dbo.Categoria SET Nombre = @Nombre, Descripcion = NULLIF(LTRIM(RTRIM(@Descripcion)), N''), Activo = @Activo
    WHERE CategoriaId = @CategoriaId;
    IF @@ROWCOUNT = 0 THROW 51001, N'La categoría no existe.', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Categoria_Eliminar
    @CategoriaId INT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM dbo.Producto WHERE CategoriaId = @CategoriaId)
        THROW 51007, N'La categoría tiene productos asociados: no se puede eliminar, solo desactivar.', 1;
    DELETE FROM dbo.Categoria WHERE CategoriaId = @CategoriaId;
    IF @@ROWCOUNT = 0 THROW 51001, N'La categoría no existe.', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Categoria_Listar
    @Buscar NVARCHAR(60) = NULL,
    @Activo BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Buscar = NULLIF(LTRIM(RTRIM(@Buscar)), N'');
    SELECT c.CategoriaId, c.Nombre, c.Descripcion, c.Activo,
           (SELECT COUNT(*) FROM dbo.Producto p WHERE p.CategoriaId = c.CategoriaId) AS Productos
    FROM dbo.Categoria c
    WHERE (@Activo IS NULL OR c.Activo = @Activo)
      AND (@Buscar IS NULL OR c.Nombre LIKE N'%' + @Buscar + N'%')
    ORDER BY c.Nombre;
END
GO

/* =====================================================================
   PRODUCTOS
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_Producto_Crear
    @SKU              VARCHAR(20),
    @Nombre           NVARCHAR(120),
    @Descripcion      NVARCHAR(500) = NULL,
    @Especificaciones NVARCHAR(1000) = NULL,
    @MarcaId          INT,
    @CategoriaId      INT,
    @Precio           DECIMAL(12,2),
    @Costo            DECIMAL(12,2),
    @StockInicial     INT = 0,
    @StockMinimo      INT = 0,
    @Destacado        BIT = 0,
    @ImagenUrl        NVARCHAR(400) = NULL,
    @UsuarioId        INT,
    @ProductoId       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SELECT @SKU = UPPER(LTRIM(RTRIM(@SKU))), @Nombre = LTRIM(RTRIM(@Nombre)), @ImagenUrl = NULLIF(LTRIM(RTRIM(@ImagenUrl)), N'');

    IF ISNULL(@SKU, '') = '' OR LEN(@SKU) < 3 OR @SKU LIKE '% %'
        THROW 51000, N'El SKU es obligatorio, de al menos 3 caracteres y sin espacios.', 1;
    IF ISNULL(@Nombre, N'') = N'' THROW 51000, N'El nombre del producto es obligatorio.', 1;
    IF @Precio IS NULL OR @Precio <= 0 THROW 51000, N'El precio debe ser mayor que cero.', 1;
    IF @Costo IS NULL OR @Costo < 0 THROW 51000, N'El costo no puede ser negativo.', 1;
    IF ISNULL(@StockInicial, -1) < 0 OR ISNULL(@StockMinimo, -1) < 0
        THROW 51000, N'La existencia inicial y el mínimo no pueden ser negativos.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Marca WHERE MarcaId = @MarcaId AND Activo = 1)
        THROW 51001, N'La marca no existe o está inactiva.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Categoria WHERE CategoriaId = @CategoriaId AND Activo = 1)
        THROW 51001, N'La categoría no existe o está inactiva.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId AND RolId = 1 AND Activo = 1)
        THROW 51006, N'Solo un administrador puede crear productos.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        IF EXISTS (SELECT 1 FROM dbo.Producto WITH (UPDLOCK, HOLDLOCK) WHERE SKU = @SKU)
            THROW 51002, N'Ya existe un producto con ese SKU.', 1;

        INSERT INTO dbo.Producto (SKU, Nombre, Descripcion, Especificaciones, MarcaId, CategoriaId, Precio, Costo, Destacado)
        VALUES (@SKU, @Nombre, NULLIF(LTRIM(RTRIM(@Descripcion)), N''), NULLIF(LTRIM(RTRIM(@Especificaciones)), N''),
                @MarcaId, @CategoriaId, @Precio, @Costo, ISNULL(@Destacado, 0));
        SET @ProductoId = SCOPE_IDENTITY();

        INSERT INTO dbo.Inventario (ProductoId, Existencia, StockMinimo) VALUES (@ProductoId, @StockInicial, @StockMinimo);

        IF @StockInicial > 0
            INSERT INTO dbo.MovimientoInventario (ProductoId, Tipo, Cantidad, ExistenciaResultante, UsuarioId, Motivo)
            VALUES (@ProductoId, 'ENTRADA', @StockInicial, @StockInicial, @UsuarioId, N'Inventario inicial');

        IF @ImagenUrl IS NOT NULL
            INSERT INTO dbo.ProductoImagen (ProductoId, Url, EsPrincipal, Orden) VALUES (@ProductoId, @ImagenUrl, 1, 1);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* Si cambia el precio, el trigger TR_Producto_AuditoriaPrecio deja el rastro.
   La existencia NO se cambia aquí: solo mediante movimientos de inventario. */
CREATE OR ALTER PROCEDURE dbo.usp_Producto_Actualizar
    @ProductoId       INT,
    @SKU              VARCHAR(20),
    @Nombre           NVARCHAR(120),
    @Descripcion      NVARCHAR(500) = NULL,
    @Especificaciones NVARCHAR(1000) = NULL,
    @MarcaId          INT,
    @CategoriaId      INT,
    @Precio           DECIMAL(12,2),
    @Costo            DECIMAL(12,2),
    @StockMinimo      INT = 0,
    @Destacado        BIT = 0,
    @ImagenUrl        NVARCHAR(400) = NULL,
    @UsuarioId        INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SELECT @SKU = UPPER(LTRIM(RTRIM(@SKU))), @Nombre = LTRIM(RTRIM(@Nombre)), @ImagenUrl = NULLIF(LTRIM(RTRIM(@ImagenUrl)), N'');

    IF ISNULL(@SKU, '') = '' OR LEN(@SKU) < 3 OR @SKU LIKE '% %'
        THROW 51000, N'El SKU es obligatorio, de al menos 3 caracteres y sin espacios.', 1;
    IF ISNULL(@Nombre, N'') = N'' THROW 51000, N'El nombre del producto es obligatorio.', 1;
    IF @Precio IS NULL OR @Precio <= 0 THROW 51000, N'El precio debe ser mayor que cero.', 1;
    IF @Costo IS NULL OR @Costo < 0 THROW 51000, N'El costo no puede ser negativo.', 1;
    IF ISNULL(@StockMinimo, -1) < 0 THROW 51000, N'El mínimo de inventario no puede ser negativo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE ProductoId = @ProductoId)
        THROW 51001, N'El producto no existe.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Producto WHERE SKU = @SKU AND ProductoId <> @ProductoId)
        THROW 51002, N'Ya existe otro producto con ese SKU.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Marca WHERE MarcaId = @MarcaId)
        THROW 51001, N'La marca no existe.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Categoria WHERE CategoriaId = @CategoriaId)
        THROW 51001, N'La categoría no existe.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId AND RolId = 1 AND Activo = 1)
        THROW 51006, N'Solo un administrador puede modificar productos.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'UsuarioId', @value = @UsuarioId;

        UPDATE dbo.Producto
        SET SKU = @SKU, Nombre = @Nombre, Descripcion = NULLIF(LTRIM(RTRIM(@Descripcion)), N''),
            Especificaciones = NULLIF(LTRIM(RTRIM(@Especificaciones)), N''), MarcaId = @MarcaId, CategoriaId = @CategoriaId,
            Precio = @Precio, Costo = @Costo, Destacado = ISNULL(@Destacado, 0)
        WHERE ProductoId = @ProductoId;

        UPDATE dbo.Inventario SET StockMinimo = @StockMinimo WHERE ProductoId = @ProductoId;

        IF @ImagenUrl IS NOT NULL
        BEGIN
            UPDATE dbo.ProductoImagen SET Url = @ImagenUrl WHERE ProductoId = @ProductoId AND EsPrincipal = 1;
            IF @@ROWCOUNT = 0
                INSERT INTO dbo.ProductoImagen (ProductoId, Url, EsPrincipal, Orden) VALUES (@ProductoId, @ImagenUrl, 1, 1);
        END
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Producto_CambiarEstado
    @ProductoId INT,
    @Activo     BIT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.Producto SET Activo = @Activo WHERE ProductoId = @ProductoId;
    IF @@ROWCOUNT = 0 THROW 51001, N'El producto no existe.', 1;
END
GO

/* Cambio masivo de precios: una sola sentencia UPDATE afecta varias filas y el
   trigger de auditoría registra una fila por cada producto modificado. */
CREATE OR ALTER PROCEDURE dbo.usp_Producto_AjustarPrecioCategoria
    @CategoriaId INT,
    @Porcentaje  DECIMAL(6,2),     -- positivo sube, negativo baja
    @UsuarioId   INT,
    @Afectados   INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @Porcentaje IS NULL OR @Porcentaje = 0 OR @Porcentaje <= -90 OR @Porcentaje > 200
        THROW 51000, N'El porcentaje debe ser distinto de 0 y estar entre -90 y 200.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Categoria WHERE CategoriaId = @CategoriaId)
        THROW 51001, N'La categoría no existe.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId AND RolId = 1 AND Activo = 1)
        THROW 51006, N'Solo un administrador puede cambiar precios.', 1;

    EXEC sys.sp_set_session_context @key = N'UsuarioId', @value = @UsuarioId;
    UPDATE dbo.Producto
    SET Precio = ROUND(Precio * (1 + @Porcentaje / 100.0), 0)
    WHERE CategoriaId = @CategoriaId AND Activo = 1;
    SET @Afectados = @@ROWCOUNT;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Producto_Obtener
    @ProductoId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.ProductoId, p.SKU, p.Nombre, p.Descripcion, p.Especificaciones, p.MarcaId, m.Nombre AS Marca,
           p.CategoriaId, c.Nombre AS Categoria, p.Precio, p.Costo, p.Destacado, p.Activo,
           i.Existencia, i.StockMinimo, img.Url AS ImagenUrl
    FROM dbo.Producto p
    JOIN dbo.Marca m ON m.MarcaId = p.MarcaId
    JOIN dbo.Categoria c ON c.CategoriaId = p.CategoriaId
    JOIN dbo.Inventario i ON i.ProductoId = p.ProductoId
    LEFT JOIN dbo.ProductoImagen img ON img.ProductoId = p.ProductoId AND img.EsPrincipal = 1
    WHERE p.ProductoId = @ProductoId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Producto_ListarAdmin
    @Buscar      NVARCHAR(100) = NULL,
    @MarcaId     INT = NULL,
    @CategoriaId INT = NULL,
    @Activo      BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Buscar = NULLIF(LTRIM(RTRIM(@Buscar)), N'');
    SELECT p.ProductoId, p.SKU, p.Nombre, m.Nombre AS Marca, c.Nombre AS Categoria, p.Precio, p.Costo,
           i.Existencia, i.StockMinimo, p.Destacado, p.Activo
    FROM dbo.Producto p
    JOIN dbo.Marca m ON m.MarcaId = p.MarcaId
    JOIN dbo.Categoria c ON c.CategoriaId = p.CategoriaId
    JOIN dbo.Inventario i ON i.ProductoId = p.ProductoId
    WHERE (@Activo IS NULL OR p.Activo = @Activo)
      AND (@MarcaId IS NULL OR p.MarcaId = @MarcaId)
      AND (@CategoriaId IS NULL OR p.CategoriaId = @CategoriaId)
      AND (@Buscar IS NULL OR p.Nombre LIKE N'%' + @Buscar + N'%' OR p.SKU LIKE N'%' + @Buscar + N'%')
    ORDER BY p.Nombre;
END
GO

/* ---------------- Imágenes adicionales ---------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ProductoImagen_Agregar
    @ProductoId INT,
    @Url        NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    SET @Url = LTRIM(RTRIM(@Url));
    IF ISNULL(@Url, N'') = N'' THROW 51000, N'La URL o ruta de la imagen es obligatoria.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE ProductoId = @ProductoId)
        THROW 51001, N'El producto no existe.', 1;
    INSERT INTO dbo.ProductoImagen (ProductoId, Url, EsPrincipal, Orden)
    SELECT @ProductoId, @Url,
           CASE WHEN EXISTS (SELECT 1 FROM dbo.ProductoImagen WHERE ProductoId = @ProductoId AND EsPrincipal = 1) THEN 0 ELSE 1 END,
           ISNULL((SELECT MAX(Orden) FROM dbo.ProductoImagen WHERE ProductoId = @ProductoId), 0) + 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_ProductoImagen_Eliminar
    @ImagenId INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.ProductoImagen WHERE ImagenId = @ImagenId;
    IF @@ROWCOUNT = 0 THROW 51001, N'La imagen no existe.', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_ProductoImagen_Listar
    @ProductoId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ImagenId, Url, EsPrincipal, Orden FROM dbo.ProductoImagen
    WHERE ProductoId = @ProductoId ORDER BY EsPrincipal DESC, Orden;
END
GO

/* =====================================================================
   CATÁLOGO DE LA TIENDA (lee la vista vw_CatalogoDisponible)
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_Catalogo_Buscar
    @Texto           NVARCHAR(100) = NULL,
    @MarcaId         INT = NULL,
    @CategoriaId     INT = NULL,
    @PrecioMin       DECIMAL(12,2) = NULL,
    @PrecioMax       DECIMAL(12,2) = NULL,
    @SoloDestacados  BIT = 0,
    @SoloOfertas     BIT = 0,
    @SoloDisponibles BIT = 0,
    @Orden           VARCHAR(12) = 'nombre'    -- nombre | precio_asc | precio_desc | calificacion
AS
BEGIN
    SET NOCOUNT ON;
    SET @Texto = NULLIF(LTRIM(RTRIM(@Texto)), N'');
    IF @PrecioMin IS NOT NULL AND @PrecioMax IS NOT NULL AND @PrecioMin > @PrecioMax
        THROW 51000, N'El precio mínimo no puede ser mayor que el máximo.', 1;

    SELECT v.ProductoId, v.SKU, v.Nombre, v.Marca, v.Categoria, v.Precio, v.DescuentoUnitario, v.PrecioFinal,
           v.Promocion, v.Existencia, v.Disponible, v.Destacado, v.CalificacionPromedio, v.TotalResenas, v.ImagenUrl
    FROM dbo.vw_CatalogoDisponible v
    WHERE (@MarcaId IS NULL OR v.MarcaId = @MarcaId)
      AND (@CategoriaId IS NULL OR v.CategoriaId = @CategoriaId)
      AND (@PrecioMin IS NULL OR v.PrecioFinal >= @PrecioMin)
      AND (@PrecioMax IS NULL OR v.PrecioFinal <= @PrecioMax)
      AND (ISNULL(@SoloDestacados, 0) = 0 OR v.Destacado = 1)
      AND (ISNULL(@SoloOfertas, 0) = 0 OR v.DescuentoUnitario > 0)
      AND (ISNULL(@SoloDisponibles, 0) = 0 OR v.Disponible = 1)
      AND (@Texto IS NULL
           OR v.Nombre LIKE N'%' + @Texto + N'%'
           OR v.Descripcion LIKE N'%' + @Texto + N'%'
           OR v.Especificaciones LIKE N'%' + @Texto + N'%'
           OR v.Marca LIKE N'%' + @Texto + N'%'
           OR v.Categoria LIKE N'%' + @Texto + N'%'
           OR v.SKU LIKE N'%' + @Texto + N'%')
    ORDER BY CASE WHEN @Orden = 'precio_asc'  THEN v.PrecioFinal END ASC,
             CASE WHEN @Orden = 'precio_desc' THEN v.PrecioFinal END DESC,
             CASE WHEN @Orden = 'calificacion' THEN v.CalificacionPromedio END DESC,
             v.Nombre;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Catalogo_Detalle
    @ProductoId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.ProductoId, v.SKU, v.Nombre, v.Descripcion, v.Especificaciones, v.MarcaId, v.Marca, v.CategoriaId, v.Categoria,
           v.Precio, v.DescuentoUnitario, v.PrecioFinal, v.Promocion, v.Existencia, v.Disponible, v.Destacado,
           v.CalificacionPromedio, v.TotalResenas, v.ImagenUrl
    FROM dbo.vw_CatalogoDisponible v
    WHERE v.ProductoId = @ProductoId;
END
GO

/* =====================================================================
   CARRITO PERSISTENTE
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_Carrito_Agregar
    @ClienteId  INT,
    @ProductoId INT,
    @Cantidad   INT = 1
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @Cantidad IS NULL OR @Cantidad <= 0 THROW 51000, N'La cantidad debe ser mayor que cero.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Cliente WHERE ClienteId = @ClienteId AND Activo = 1)
        THROW 51001, N'El cliente no existe o está inactivo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.vw_CatalogoDisponible WHERE ProductoId = @ProductoId)
        THROW 51001, N'El producto no existe o no está disponible para la venta.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @CarritoId INT = (SELECT CarritoId FROM dbo.Carrito WITH (UPDLOCK, HOLDLOCK) WHERE ClienteId = @ClienteId);
        IF @CarritoId IS NULL
        BEGIN
            INSERT INTO dbo.Carrito (ClienteId) VALUES (@ClienteId);
            SET @CarritoId = SCOPE_IDENTITY();
        END

        DECLARE @EnCarrito INT = ISNULL((SELECT Cantidad FROM dbo.DetalleCarrito WHERE CarritoId = @CarritoId AND ProductoId = @ProductoId), 0);
        DECLARE @Existencia INT = (SELECT Existencia FROM dbo.Inventario WHERE ProductoId = @ProductoId);
        IF @EnCarrito + @Cantidad > @Existencia
        BEGIN
            DECLARE @Msg NVARCHAR(200) = FORMATMESSAGE(N'Existencia insuficiente: hay %d unidades disponibles y el carrito ya tiene %d.', @Existencia, @EnCarrito);
            THROW 51003, @Msg, 1;
        END

        IF @EnCarrito > 0
            UPDATE dbo.DetalleCarrito SET Cantidad = Cantidad + @Cantidad WHERE CarritoId = @CarritoId AND ProductoId = @ProductoId;
        ELSE
            INSERT INTO dbo.DetalleCarrito (CarritoId, ProductoId, Cantidad) VALUES (@CarritoId, @ProductoId, @Cantidad);

        UPDATE dbo.Carrito SET FechaActualizacion = SYSDATETIME() WHERE CarritoId = @CarritoId;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Carrito_CambiarCantidad
    @ClienteId  INT,
    @ProductoId INT,
    @Cantidad   INT        -- 0 elimina la línea
AS
BEGIN
    SET NOCOUNT ON;
    IF @Cantidad IS NULL OR @Cantidad < 0 THROW 51000, N'La cantidad no puede ser negativa.', 1;
    DECLARE @CarritoId INT = (SELECT CarritoId FROM dbo.Carrito WHERE ClienteId = @ClienteId);
    IF @CarritoId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.DetalleCarrito WHERE CarritoId = @CarritoId AND ProductoId = @ProductoId)
        THROW 51001, N'El producto no está en el carrito.', 1;

    IF @Cantidad = 0
        DELETE FROM dbo.DetalleCarrito WHERE CarritoId = @CarritoId AND ProductoId = @ProductoId;
    ELSE
    BEGIN
        DECLARE @Existencia INT = (SELECT Existencia FROM dbo.Inventario WHERE ProductoId = @ProductoId);
        IF @Cantidad > @Existencia
        BEGIN
            DECLARE @Msg NVARCHAR(200) = FORMATMESSAGE(N'Existencia insuficiente: solo hay %d unidades disponibles.', @Existencia);
            THROW 51003, @Msg, 1;
        END
        UPDATE dbo.DetalleCarrito SET Cantidad = @Cantidad WHERE CarritoId = @CarritoId AND ProductoId = @ProductoId;
    END
    UPDATE dbo.Carrito SET FechaActualizacion = SYSDATETIME() WHERE CarritoId = @CarritoId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Carrito_EliminarLinea
    @ClienteId  INT,
    @ProductoId INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE dc FROM dbo.DetalleCarrito dc JOIN dbo.Carrito c ON c.CarritoId = dc.CarritoId
    WHERE c.ClienteId = @ClienteId AND dc.ProductoId = @ProductoId;
    IF @@ROWCOUNT = 0 THROW 51001, N'El producto no está en el carrito.', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Carrito_Vaciar
    @ClienteId INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE dc FROM dbo.DetalleCarrito dc JOIN dbo.Carrito c ON c.CarritoId = dc.CarritoId
    WHERE c.ClienteId = @ClienteId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Carrito_Obtener
    @ClienteId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Hoy DATE = SYSDATETIME();
    SELECT p.ProductoId, p.SKU, p.Nombre, img.Url AS ImagenUrl, dc.Cantidad, p.Precio,
           ISNULL(pm.Descuento, 0) AS DescuentoUnitario, p.Precio - ISNULL(pm.Descuento, 0) AS PrecioFinal,
           pm.Promocion, dc.Cantidad * (p.Precio - ISNULL(pm.Descuento, 0)) AS TotalLinea,
           i.Existencia,
           CAST(CASE WHEN p.Activo = 1 AND i.Existencia >= dc.Cantidad THEN 1 ELSE 0 END AS BIT) AS Disponible
    FROM dbo.Carrito c
    JOIN dbo.DetalleCarrito dc ON dc.CarritoId = c.CarritoId
    JOIN dbo.Producto p ON p.ProductoId = dc.ProductoId
    JOIN dbo.Inventario i ON i.ProductoId = p.ProductoId
    LEFT JOIN dbo.ProductoImagen img ON img.ProductoId = p.ProductoId AND img.EsPrincipal = 1
    OUTER APPLY dbo.fn_MejorPromocion(p.ProductoId, @Hoy) pm
    WHERE c.ClienteId = @ClienteId
    ORDER BY dc.FechaAgregado;
END
GO

/* Resumen del carrito: subtotal, descuento, envío (según la zona de la dirección) y total. */
CREATE OR ALTER PROCEDURE dbo.usp_Carrito_Resumen
    @ClienteId   INT,
    @DireccionId INT = NULL    -- NULL = dirección predeterminada
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Hoy DATE = SYSDATETIME();
    DECLARE @Envio DECIMAL(10,2), @Zona NVARCHAR(60), @Dias TINYINT;

    SELECT TOP (1) @Envio = z.Tarifa, @Zona = z.Nombre, @Dias = z.DiasEstimados, @DireccionId = d.DireccionId
    FROM dbo.Direccion d JOIN dbo.ZonaEnvio z ON z.ZonaEnvioId = d.ZonaEnvioId
    WHERE d.ClienteId = @ClienteId AND d.Activo = 1 AND (@DireccionId IS NULL OR d.DireccionId = @DireccionId)
    ORDER BY d.Predeterminada DESC, d.DireccionId;

    SELECT COUNT(*) AS Lineas,
           ISNULL(SUM(dc.Cantidad), 0) AS Unidades,
           ISNULL(SUM(dc.Cantidad * p.Precio), 0) AS Subtotal,
           ISNULL(SUM(dc.Cantidad * ISNULL(pm.Descuento, 0)), 0) AS Descuento,
           CASE WHEN COUNT(*) = 0 THEN 0 ELSE ISNULL(@Envio, 0) END AS CostoEnvio,
           ISNULL(SUM(dc.Cantidad * (p.Precio - ISNULL(pm.Descuento, 0))), 0)
               + CASE WHEN COUNT(*) = 0 THEN 0 ELSE ISNULL(@Envio, 0) END AS Total,
           @DireccionId AS DireccionId, @Zona AS Zona, @Dias AS DiasEstimados
    FROM dbo.Carrito c
    JOIN dbo.DetalleCarrito dc ON dc.CarritoId = c.CarritoId
    JOIN dbo.Producto p ON p.ProductoId = dc.ProductoId
    OUTER APPLY dbo.fn_MejorPromocion(p.ProductoId, @Hoy) pm
    WHERE c.ClienteId = @ClienteId;
END
GO

/* =====================================================================
   PROMOCIONES
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_Promocion_Crear
    @Nombre        NVARCHAR(80),
    @TipoDescuento CHAR(1),          -- P = porcentaje, M = monto
    @Valor         DECIMAL(12,2),
    @FechaInicio   DATE,
    @FechaFin      DATE,
    @PromocionId   INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Nombre = LTRIM(RTRIM(@Nombre));
    IF ISNULL(@Nombre, N'') = N'' THROW 51000, N'El nombre de la promoción es obligatorio.', 1;
    IF @TipoDescuento NOT IN ('P', 'M') THROW 51000, N'El tipo de descuento debe ser P (porcentaje) o M (monto).', 1;
    IF @Valor IS NULL OR @Valor <= 0 THROW 51000, N'El valor del descuento debe ser mayor que cero.', 1;
    IF @TipoDescuento = 'P' AND @Valor > 100 THROW 51000, N'Un descuento porcentual no puede ser mayor que 100.', 1;
    IF @FechaInicio IS NULL OR @FechaFin IS NULL OR @FechaFin < @FechaInicio
        THROW 51000, N'El período no es válido: la fecha final debe ser igual o posterior a la inicial.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Promocion WHERE Nombre = @Nombre)
        THROW 51002, N'Ya existe una promoción con ese nombre.', 1;

    INSERT INTO dbo.Promocion (Nombre, TipoDescuento, Valor, FechaInicio, FechaFin)
    VALUES (@Nombre, @TipoDescuento, @Valor, @FechaInicio, @FechaFin);
    SET @PromocionId = SCOPE_IDENTITY();
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Promocion_Actualizar
    @PromocionId   INT,
    @Nombre        NVARCHAR(80),
    @TipoDescuento CHAR(1),
    @Valor         DECIMAL(12,2),
    @FechaInicio   DATE,
    @FechaFin      DATE,
    @Activo        BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET @Nombre = LTRIM(RTRIM(@Nombre));
    IF ISNULL(@Nombre, N'') = N'' THROW 51000, N'El nombre de la promoción es obligatorio.', 1;
    IF @TipoDescuento NOT IN ('P', 'M') THROW 51000, N'El tipo de descuento debe ser P (porcentaje) o M (monto).', 1;
    IF @Valor IS NULL OR @Valor <= 0 THROW 51000, N'El valor del descuento debe ser mayor que cero.', 1;
    IF @TipoDescuento = 'P' AND @Valor > 100 THROW 51000, N'Un descuento porcentual no puede ser mayor que 100.', 1;
    IF @FechaInicio IS NULL OR @FechaFin IS NULL OR @FechaFin < @FechaInicio
        THROW 51000, N'El período no es válido: la fecha final debe ser igual o posterior a la inicial.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Promocion WHERE Nombre = @Nombre AND PromocionId <> @PromocionId)
        THROW 51002, N'Ya existe otra promoción con ese nombre.', 1;

    UPDATE dbo.Promocion
    SET Nombre = @Nombre, TipoDescuento = @TipoDescuento, Valor = @Valor,
        FechaInicio = @FechaInicio, FechaFin = @FechaFin, Activo = @Activo
    WHERE PromocionId = @PromocionId;
    IF @@ROWCOUNT = 0 THROW 51001, N'La promoción no existe.', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Promocion_Listar
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Hoy DATE = SYSDATETIME();
    SELECT m.PromocionId, m.Nombre, m.TipoDescuento, m.Valor, m.FechaInicio, m.FechaFin, m.Activo,
           CASE WHEN m.Activo = 0 THEN N'Inactiva'
                WHEN @Hoy < m.FechaInicio THEN N'Programada'
                WHEN @Hoy > m.FechaFin THEN N'Vencida'
                ELSE N'Vigente' END AS Vigencia,
           (SELECT COUNT(*) FROM dbo.PromocionProducto pp WHERE pp.PromocionId = m.PromocionId) AS Productos
    FROM dbo.Promocion m
    ORDER BY m.FechaInicio DESC, m.PromocionId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Promocion_AsignarProducto
    @PromocionId INT,
    @ProductoId  INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Promocion WHERE PromocionId = @PromocionId) THROW 51001, N'La promoción no existe.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE ProductoId = @ProductoId) THROW 51001, N'El producto no existe.', 1;
    IF EXISTS (SELECT 1 FROM dbo.PromocionProducto WHERE PromocionId = @PromocionId AND ProductoId = @ProductoId)
        THROW 51002, N'El producto ya está en la promoción.', 1;
    INSERT INTO dbo.PromocionProducto (PromocionId, ProductoId) VALUES (@PromocionId, @ProductoId);
END
GO

/* Agrega a la promoción todos los productos activos de una categoría que aún no estén. */
CREATE OR ALTER PROCEDURE dbo.usp_Promocion_AsignarCategoria
    @PromocionId INT,
    @CategoriaId INT,
    @Agregados   INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Promocion WHERE PromocionId = @PromocionId) THROW 51001, N'La promoción no existe.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Categoria WHERE CategoriaId = @CategoriaId) THROW 51001, N'La categoría no existe.', 1;
    INSERT INTO dbo.PromocionProducto (PromocionId, ProductoId)
    SELECT @PromocionId, p.ProductoId
    FROM dbo.Producto p
    WHERE p.CategoriaId = @CategoriaId AND p.Activo = 1
      AND NOT EXISTS (SELECT 1 FROM dbo.PromocionProducto pp WHERE pp.PromocionId = @PromocionId AND pp.ProductoId = p.ProductoId);
    SET @Agregados = @@ROWCOUNT;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Promocion_QuitarProducto
    @PromocionId INT,
    @ProductoId  INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.PromocionProducto WHERE PromocionId = @PromocionId AND ProductoId = @ProductoId;
    IF @@ROWCOUNT = 0 THROW 51001, N'El producto no está en la promoción.', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Promocion_ListarProductos
    @PromocionId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.ProductoId, p.SKU, p.Nombre, c.Nombre AS Categoria, p.Precio
    FROM dbo.PromocionProducto pp
    JOIN dbo.Producto p ON p.ProductoId = pp.ProductoId
    JOIN dbo.Categoria c ON c.CategoriaId = p.CategoriaId
    WHERE pp.PromocionId = @PromocionId
    ORDER BY c.Nombre, p.Nombre;
END
GO

/* =====================================================================
   PEDIDOS
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_MetodoPago_Listar
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MetodoPagoId, Nombre, AprobacionInmediata FROM dbo.MetodoPago WHERE Activo = 1 ORDER BY MetodoPagoId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_EstadoPedido_Listar
AS
BEGIN
    SET NOCOUNT ON;
    SELECT EstadoId, Nombre, EsFinal FROM dbo.EstadoPedido ORDER BY EstadoId;
END
GO

/* ---------------------------------------------------------------------
   CHECKOUT: confirmación del pedido en UNA transacción indivisible.
   Pasos (todo o nada):
     1. Toma las líneas del carrito con precio, costo y descuento vigentes.
     2. Descuenta existencias con un UPDATE condicional (Existencia >= Cantidad).
        Ese UPDATE es atómico y bloquea las filas: dos compras simultáneas no
        pueden vender la misma unidad. Si alguna línea no se pudo descontar,
        THROW -> ROLLBACK de todo (ningún inventario queda afectado).
     3. Inserta encabezado, detalle (precio/descuento/costo históricos),
        movimientos de inventario, pago simulado y envío.
     4. Si el método de pago aprueba de inmediato, pasa a Confirmado.
     5. Vacía el carrito.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Pedido_Confirmar
    @ClienteId    INT,
    @DireccionId  INT,
    @MetodoPagoId INT,
    @PedidoId     INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @Ahora DATETIME2(0) = SYSDATETIME();
    DECLARE @Hoy DATE = @Ahora;
    DECLARE @UsuarioId INT, @ZonaEnvioId INT, @CostoEnvio DECIMAL(10,2), @Inmediata BIT;
    DECLARE @Msg NVARCHAR(2000);

    SELECT @UsuarioId = UsuarioId FROM dbo.Cliente WHERE ClienteId = @ClienteId AND Activo = 1;
    IF @UsuarioId IS NULL THROW 51001, N'El cliente no existe o está inactivo.', 1;

    SELECT @ZonaEnvioId = z.ZonaEnvioId, @CostoEnvio = z.Tarifa
    FROM dbo.Direccion d JOIN dbo.ZonaEnvio z ON z.ZonaEnvioId = d.ZonaEnvioId
    WHERE d.DireccionId = @DireccionId AND d.ClienteId = @ClienteId AND d.Activo = 1;
    IF @ZonaEnvioId IS NULL THROW 51001, N'La dirección de entrega no existe o no pertenece al cliente.', 1;

    SELECT @Inmediata = AprobacionInmediata FROM dbo.MetodoPago WHERE MetodoPagoId = @MetodoPagoId AND Activo = 1;
    IF @Inmediata IS NULL THROW 51001, N'El método de pago no existe o está inactivo.', 1;

    DECLARE @Lineas TABLE (ProductoId INT PRIMARY KEY, Nombre NVARCHAR(120), Activo BIT, Cantidad INT,
                           Precio DECIMAL(12,2), Costo DECIMAL(12,2), Descuento DECIMAL(12,2), PromocionId INT NULL);
    DECLARE @Descontado TABLE (ProductoId INT PRIMARY KEY, ExistenciaNueva INT);

    BEGIN TRY
        BEGIN TRANSACTION;

        /* Bloquea el carrito: un doble clic en "Confirmar" no puede crear dos pedidos. */
        DECLARE @CarritoId INT = (SELECT CarritoId FROM dbo.Carrito WITH (UPDLOCK, HOLDLOCK) WHERE ClienteId = @ClienteId);

        INSERT INTO @Lineas (ProductoId, Nombre, Activo, Cantidad, Precio, Costo, Descuento, PromocionId)
        SELECT p.ProductoId, p.Nombre, p.Activo, dc.Cantidad, p.Precio, p.Costo, ISNULL(pm.Descuento, 0), pm.PromocionId
        FROM dbo.DetalleCarrito dc
        JOIN dbo.Producto p ON p.ProductoId = dc.ProductoId
        OUTER APPLY dbo.fn_MejorPromocion(p.ProductoId, @Hoy) pm
        WHERE dc.CarritoId = @CarritoId;

        DECLARE @NumLineas INT = (SELECT COUNT(*) FROM @Lineas);
        IF @NumLineas = 0 THROW 51005, N'El carrito está vacío.', 1;

        SELECT @Msg = STRING_AGG(Nombre, N', ') FROM @Lineas WHERE Activo = 0;
        IF @Msg IS NOT NULL
        BEGIN
            SET @Msg = N'Estos productos ya no están a la venta: ' + @Msg + N'. Quítelos del carrito.';
            THROW 51006, @Msg, 1;
        END

        /* Descuento atómico de existencias (protección contra sobreventa). */
        UPDATE i
        SET i.Existencia = i.Existencia - l.Cantidad, i.FechaActualizacion = @Ahora
        OUTPUT inserted.ProductoId, inserted.Existencia INTO @Descontado (ProductoId, ExistenciaNueva)
        FROM dbo.Inventario i
        JOIN @Lineas l ON l.ProductoId = i.ProductoId
        WHERE i.Existencia >= l.Cantidad;

        IF @@ROWCOUNT <> @NumLineas
        BEGIN
            SELECT @Msg = STRING_AGG(l.Nombre + N' (solicitado ' + CAST(l.Cantidad AS NVARCHAR(10)) + N', disponible '
                                     + CAST(i.Existencia AS NVARCHAR(10)) + N')', N'; ')
            FROM @Lineas l JOIN dbo.Inventario i ON i.ProductoId = l.ProductoId
            WHERE NOT EXISTS (SELECT 1 FROM @Descontado d WHERE d.ProductoId = l.ProductoId);
            SET @Msg = N'Existencia insuficiente: ' + @Msg + N'. No se registró el pedido.';
            THROW 51003, @Msg, 1;
        END

        /* Contexto para el trigger de historial de estados. */
        EXEC sys.sp_set_session_context @key = N'UsuarioId', @value = @UsuarioId;
        EXEC sys.sp_set_session_context @key = N'Comentario', @value = N'Pedido creado desde el carrito';

        INSERT INTO dbo.Pedido (ClienteId, DireccionId, EstadoId, FechaPedido, Subtotal, DescuentoTotal, CostoEnvio)
        SELECT @ClienteId, @DireccionId, 1, @Ahora, SUM(Cantidad * Precio), SUM(Cantidad * Descuento), @CostoEnvio
        FROM @Lineas;
        SET @PedidoId = SCOPE_IDENTITY();

        /* El detalle guarda precio, descuento y costo del momento: son históricos. */
        INSERT INTO dbo.DetallePedido (PedidoId, ProductoId, Cantidad, PrecioUnitario, DescuentoUnitario, CostoUnitario, PromocionId)
        SELECT @PedidoId, ProductoId, Cantidad, Precio, Descuento, Costo, PromocionId FROM @Lineas;

        INSERT INTO dbo.MovimientoInventario (ProductoId, Tipo, Cantidad, ExistenciaResultante, Fecha, UsuarioId, Motivo, PedidoId)
        SELECT l.ProductoId, 'SALIDA', -l.Cantidad, d.ExistenciaNueva, @Ahora, @UsuarioId,
               N'Venta, pedido #' + CAST(@PedidoId AS NVARCHAR(10)), @PedidoId
        FROM @Lineas l JOIN @Descontado d ON d.ProductoId = l.ProductoId;

        INSERT INTO dbo.Pago (PedidoId, MetodoPagoId, Monto, Estado, Referencia, Fecha)
        SELECT @PedidoId, @MetodoPagoId, Total, CASE WHEN @Inmediata = 1 THEN 'APROBADO' ELSE 'PENDIENTE' END,
               'PAG-' + CAST(YEAR(@Ahora) AS CHAR(4)) + '-' + RIGHT('00000' + CAST(@PedidoId AS VARCHAR(10)), 5), @Ahora
        FROM dbo.Pedido WHERE PedidoId = @PedidoId;

        INSERT INTO dbo.Envio (PedidoId, ZonaEnvioId) VALUES (@PedidoId, @ZonaEnvioId);

        IF @Inmediata = 1
        BEGIN
            EXEC sys.sp_set_session_context @key = N'Comentario', @value = N'Pago simulado aprobado';
            UPDATE dbo.Pedido SET EstadoId = 2 WHERE PedidoId = @PedidoId;
        END

        DELETE FROM dbo.DetalleCarrito WHERE CarritoId = @CarritoId;
        UPDATE dbo.Carrito SET FechaActualizacion = @Ahora WHERE CarritoId = @CarritoId;

        COMMIT TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'Comentario', @value = NULL;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'Comentario', @value = NULL;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   CANCELACIÓN: permitida solo antes del envío. Reintegra existencias UNA
   sola vez: el cambio de estado y el reintegro van en la misma transacción
   y un pedido ya cancelado se rechaza, así que no hay doble devolución.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Pedido_Cancelar
    @PedidoId  INT,
    @UsuarioId INT,
    @Motivo    NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @Ahora DATETIME2(0) = SYSDATETIME();
    DECLARE @Estado TINYINT, @NombreEstado NVARCHAR(30), @Duenio INT, @RolId TINYINT, @Msg NVARCHAR(400);
    SET @Motivo = LTRIM(RTRIM(@Motivo));
    IF ISNULL(@Motivo, N'') = N'' THROW 51000, N'Debe indicar el motivo de la cancelación.', 1;

    SELECT @RolId = RolId FROM dbo.Usuario WHERE UsuarioId = @UsuarioId AND Activo = 1;
    IF @RolId IS NULL THROW 51001, N'El usuario no existe o está inactivo.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* UPDLOCK: si dos sesiones cancelan a la vez, la segunda espera y luego ve el pedido ya cancelado. */
        SELECT @Estado = o.EstadoId, @NombreEstado = e.Nombre, @Duenio = c.UsuarioId
        FROM dbo.Pedido o WITH (UPDLOCK, HOLDLOCK)
        JOIN dbo.EstadoPedido e ON e.EstadoId = o.EstadoId
        JOIN dbo.Cliente c ON c.ClienteId = o.ClienteId
        WHERE o.PedidoId = @PedidoId;

        IF @Estado IS NULL THROW 51001, N'El pedido no existe.', 1;
        IF @RolId <> 1 AND @Duenio <> @UsuarioId THROW 51006, N'Solo puede cancelar sus propios pedidos.', 1;
        IF @Estado = 6 THROW 51004, N'El pedido ya está cancelado; las existencias se reintegraron una sola vez.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.TransicionEstado WHERE EstadoOrigenId = @Estado AND EstadoDestinoId = 6)
        BEGIN
            SET @Msg = N'No se puede cancelar un pedido en estado "' + @NombreEstado + N'": la cancelación solo es posible antes del envío.';
            THROW 51004, @Msg, 1;
        END

        SET @Msg = N'Cancelado: ' + @Motivo;
        EXEC sys.sp_set_session_context @key = N'UsuarioId', @value = @UsuarioId;
        EXEC sys.sp_set_session_context @key = N'Comentario', @value = @Msg;
        UPDATE dbo.Pedido SET EstadoId = 6 WHERE PedidoId = @PedidoId;

        /* Reintegro de existencias y su movimiento de entrada. */
        DECLARE @Reintegrado TABLE (ProductoId INT PRIMARY KEY, ExistenciaNueva INT);
        UPDATE i
        SET i.Existencia = i.Existencia + d.Cantidad, i.FechaActualizacion = @Ahora
        OUTPUT inserted.ProductoId, inserted.Existencia INTO @Reintegrado (ProductoId, ExistenciaNueva)
        FROM dbo.Inventario i JOIN dbo.DetallePedido d ON d.ProductoId = i.ProductoId
        WHERE d.PedidoId = @PedidoId;

        INSERT INTO dbo.MovimientoInventario (ProductoId, Tipo, Cantidad, ExistenciaResultante, Fecha, UsuarioId, Motivo, PedidoId)
        SELECT d.ProductoId, 'ENTRADA', d.Cantidad, r.ExistenciaNueva, @Ahora, @UsuarioId,
               N'Reintegro por cancelación, pedido #' + CAST(@PedidoId AS NVARCHAR(10)), @PedidoId
        FROM dbo.DetallePedido d JOIN @Reintegrado r ON r.ProductoId = d.ProductoId
        WHERE d.PedidoId = @PedidoId;

        /* Pago simulado: aprobado -> reembolsado; pendiente -> anulado. */
        UPDATE dbo.Pago
        SET Estado = CASE Estado WHEN 'APROBADO' THEN 'REEMBOLSADO' WHEN 'PENDIENTE' THEN 'ANULADO' ELSE Estado END
        WHERE PedidoId = @PedidoId;

        COMMIT TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'Comentario', @value = NULL;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'Comentario', @value = NULL;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   CAMBIO DE ESTADO (administrador). Las transiciones válidas están en la
   tabla TransicionEstado; cualquier otra se rechaza con error 51004.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Pedido_CambiarEstado
    @PedidoId      INT,
    @NuevoEstadoId TINYINT,
    @UsuarioId     INT,
    @Comentario    NVARCHAR(250) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @Ahora DATETIME2(0) = SYSDATETIME();
    DECLARE @Estado TINYINT, @Origen NVARCHAR(30), @Destino NVARCHAR(30), @Msg NVARCHAR(400);

    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId AND RolId = 1 AND Activo = 1)
        THROW 51006, N'Solo un administrador puede cambiar el estado de un pedido.', 1;
    SELECT @Destino = Nombre FROM dbo.EstadoPedido WHERE EstadoId = @NuevoEstadoId;
    IF @Destino IS NULL THROW 51001, N'El estado indicado no existe.', 1;

    /* La cancelación tiene su propio procedimiento porque reintegra inventario. */
    IF @NuevoEstadoId = 6
    BEGIN
        SET @Comentario = ISNULL(NULLIF(LTRIM(RTRIM(@Comentario)), N''), N'Cancelado por el administrador');
        EXEC dbo.usp_Pedido_Cancelar @PedidoId = @PedidoId, @UsuarioId = @UsuarioId, @Motivo = @Comentario;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @Estado = o.EstadoId, @Origen = e.Nombre
        FROM dbo.Pedido o WITH (UPDLOCK, HOLDLOCK) JOIN dbo.EstadoPedido e ON e.EstadoId = o.EstadoId
        WHERE o.PedidoId = @PedidoId;
        IF @Estado IS NULL THROW 51001, N'El pedido no existe.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.TransicionEstado WHERE EstadoOrigenId = @Estado AND EstadoDestinoId = @NuevoEstadoId)
        BEGIN
            SET @Msg = N'Transición de estado inválida: de "' + @Origen + N'" no se puede pasar a "' + @Destino + N'".';
            THROW 51004, @Msg, 1;
        END

        SET @Comentario = NULLIF(LTRIM(RTRIM(@Comentario)), N'');
        EXEC sys.sp_set_session_context @key = N'UsuarioId', @value = @UsuarioId;
        EXEC sys.sp_set_session_context @key = N'Comentario', @value = @Comentario;
        UPDATE dbo.Pedido SET EstadoId = @NuevoEstadoId WHERE PedidoId = @PedidoId;

        IF @NuevoEstadoId = 2        -- Confirmado: el pago pendiente queda aprobado
            UPDATE dbo.Pago SET Estado = 'APROBADO', Fecha = @Ahora WHERE PedidoId = @PedidoId AND Estado = 'PENDIENTE';
        ELSE IF @NuevoEstadoId = 4   -- Enviado: se asigna número de guía y fecha de despacho
            UPDATE dbo.Envio
            SET NumeroGuia = ISNULL(NumeroGuia, 'TT-' + CAST(YEAR(@Ahora) AS CHAR(4)) + '-' + RIGHT('00000' + CAST(@PedidoId AS VARCHAR(10)), 5)),
                FechaDespacho = @Ahora
            WHERE PedidoId = @PedidoId;
        ELSE IF @NuevoEstadoId = 5   -- Entregado
            UPDATE dbo.Envio SET FechaEntrega = @Ahora WHERE PedidoId = @PedidoId;

        COMMIT TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'Comentario', @value = NULL;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'Comentario', @value = NULL;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Pedido_ListarPorCliente
    @ClienteId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.PedidoId, v.FechaPedido, v.EstadoId, v.Estado, v.Lineas, v.Unidades, v.Subtotal, v.DescuentoTotal, v.CostoEnvio, v.Total
    FROM dbo.vw_ResumenPedidos v
    WHERE v.ClienteId = @ClienteId
    ORDER BY v.FechaPedido DESC, v.PedidoId DESC;
END
GO

/* Encabezado completo del pedido. Si se pasa @ClienteId, solo devuelve pedidos de ese cliente. */
CREATE OR ALTER PROCEDURE dbo.usp_Pedido_Obtener
    @PedidoId  INT,
    @ClienteId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.PedidoId, v.FechaPedido, v.EstadoId, v.Estado, v.ClienteId, v.Cliente, v.Correo, c.Identificacion, c.Telefono,
           v.Lineas, v.Unidades, v.Subtotal, v.DescuentoTotal, v.CostoEnvio, v.Total,
           d.Alias AS DireccionAlias, d.Provincia, d.Canton, d.Distrito, d.Detalle AS DireccionDetalle,
           z.Nombre AS Zona, z.DiasEstimados, e.NumeroGuia, e.FechaDespacho, e.FechaEntrega,
           mp.Nombre AS MetodoPago, g.Estado AS EstadoPago, g.Referencia AS ReferenciaPago, g.Monto AS MontoPago, g.Fecha AS FechaPago,
           CAST(CASE WHEN EXISTS (SELECT 1 FROM dbo.TransicionEstado t WHERE t.EstadoOrigenId = v.EstadoId AND t.EstadoDestinoId = 6)
                     THEN 1 ELSE 0 END AS BIT) AS Cancelable
    FROM dbo.vw_ResumenPedidos v
    JOIN dbo.Pedido o ON o.PedidoId = v.PedidoId
    JOIN dbo.Cliente c ON c.ClienteId = o.ClienteId
    JOIN dbo.Direccion d ON d.DireccionId = o.DireccionId
    LEFT JOIN dbo.Envio e ON e.PedidoId = o.PedidoId
    LEFT JOIN dbo.ZonaEnvio z ON z.ZonaEnvioId = e.ZonaEnvioId
    LEFT JOIN dbo.Pago g ON g.PedidoId = o.PedidoId
    LEFT JOIN dbo.MetodoPago mp ON mp.MetodoPagoId = g.MetodoPagoId
    WHERE v.PedidoId = @PedidoId AND (@ClienteId IS NULL OR v.ClienteId = @ClienteId);
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Pedido_Detalle
    @PedidoId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.ProductoId, p.SKU, p.Nombre, d.Cantidad, d.PrecioUnitario, d.DescuentoUnitario, d.TotalLinea,
           m.Nombre AS Promocion, p.Precio AS PrecioCatalogoActual
    FROM dbo.DetallePedido d
    JOIN dbo.Producto p ON p.ProductoId = d.ProductoId
    LEFT JOIN dbo.Promocion m ON m.PromocionId = d.PromocionId
    WHERE d.PedidoId = @PedidoId
    ORDER BY p.Nombre;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Pedido_Historial
    @PedidoId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT h.Fecha, ea.Nombre AS EstadoAnterior, en.Nombre AS EstadoNuevo, u.Correo AS Usuario, h.UsuarioBD, h.Comentario
    FROM dbo.HistorialEstadoPedido h
    LEFT JOIN dbo.EstadoPedido ea ON ea.EstadoId = h.EstadoAnteriorId
    JOIN dbo.EstadoPedido en ON en.EstadoId = h.EstadoNuevoId
    LEFT JOIN dbo.Usuario u ON u.UsuarioId = h.UsuarioId
    WHERE h.PedidoId = @PedidoId
    ORDER BY h.Fecha, h.HistorialId;
END
GO

/* Estados a los que puede pasar un pedido desde su estado actual. */
CREATE OR ALTER PROCEDURE dbo.usp_Pedido_TransicionesDisponibles
    @PedidoId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT e.EstadoId, e.Nombre
    FROM dbo.Pedido o
    JOIN dbo.TransicionEstado t ON t.EstadoOrigenId = o.EstadoId
    JOIN dbo.EstadoPedido e ON e.EstadoId = t.EstadoDestinoId
    WHERE o.PedidoId = @PedidoId
    ORDER BY e.EstadoId;
END
GO

/* =====================================================================
   INVENTARIO
   ===================================================================== */
/* Registra una entrada, salida o ajuste. La existencia y su movimiento se
   guardan en la misma transacción; nunca queda existencia negativa.
   @Cantidad: positiva para ENTRADA y SALIDA; con signo para AJUSTE. */
CREATE OR ALTER PROCEDURE dbo.usp_Inventario_RegistrarMovimiento
    @ProductoId   INT,
    @Tipo         VARCHAR(10),
    @Cantidad     INT,
    @UsuarioId    INT,
    @Motivo       NVARCHAR(200),
    @MovimientoId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @Delta INT, @Nueva INT, @Msg NVARCHAR(200);
    SELECT @Tipo = UPPER(LTRIM(RTRIM(@Tipo))), @Motivo = LTRIM(RTRIM(@Motivo));

    IF @Tipo NOT IN ('ENTRADA', 'SALIDA', 'AJUSTE') THROW 51000, N'El tipo debe ser ENTRADA, SALIDA o AJUSTE.', 1;
    IF @Cantidad IS NULL OR @Cantidad = 0 THROW 51000, N'La cantidad no puede ser cero.', 1;
    IF @Tipo IN ('ENTRADA', 'SALIDA') AND @Cantidad < 0 THROW 51000, N'En entradas y salidas la cantidad debe ser positiva.', 1;
    IF ISNULL(@Motivo, N'') = N'' THROW 51000, N'El motivo del movimiento es obligatorio.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId AND RolId = 1 AND Activo = 1)
        THROW 51006, N'Solo un administrador puede registrar movimientos de inventario.', 1;

    SET @Delta = CASE @Tipo WHEN 'SALIDA' THEN -@Cantidad ELSE @Cantidad END;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.Inventario
        SET Existencia = Existencia + @Delta, FechaActualizacion = SYSDATETIME(), @Nueva = Existencia + @Delta
        WHERE ProductoId = @ProductoId AND Existencia + @Delta >= 0;

        IF @@ROWCOUNT = 0
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.Inventario WHERE ProductoId = @ProductoId)
                THROW 51001, N'El producto no existe.', 1;
            SET @Msg = FORMATMESSAGE(N'Existencia insuficiente: el movimiento dejaría el inventario en negativo (existencia actual: %d).',
                                     (SELECT Existencia FROM dbo.Inventario WHERE ProductoId = @ProductoId));
            THROW 51003, @Msg, 1;
        END

        INSERT INTO dbo.MovimientoInventario (ProductoId, Tipo, Cantidad, ExistenciaResultante, UsuarioId, Motivo)
        VALUES (@ProductoId, @Tipo, @Delta, @Nueva, @UsuarioId, @Motivo);
        SET @MovimientoId = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Inventario_Movimientos
    @ProductoId INT = NULL,
    @Tipo       VARCHAR(10) = NULL,
    @Desde      DATE = NULL,
    @Hasta      DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Tipo = NULLIF(UPPER(LTRIM(RTRIM(@Tipo))), '');
    SELECT TOP (500) m.MovimientoId, m.Fecha, p.SKU, p.Nombre AS Producto, m.Tipo, m.Cantidad, m.ExistenciaResultante,
           u.Correo AS Usuario, m.Motivo, m.PedidoId
    FROM dbo.MovimientoInventario m
    JOIN dbo.Producto p ON p.ProductoId = m.ProductoId
    JOIN dbo.Usuario u ON u.UsuarioId = m.UsuarioId
    WHERE (@ProductoId IS NULL OR m.ProductoId = @ProductoId)
      AND (@Tipo IS NULL OR m.Tipo = @Tipo)
      AND (@Desde IS NULL OR m.Fecha >= @Desde)
      AND (@Hasta IS NULL OR m.Fecha < DATEADD(DAY, 1, @Hasta))
    ORDER BY m.Fecha DESC, m.MovimientoId DESC;
END
GO

/* Alerta de productos bajo el mínimo (lee la vista). */
CREATE OR ALTER PROCEDURE dbo.usp_Inventario_BajoMinimo
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ProductoId, SKU, Nombre, Marca, Categoria, Existencia, StockMinimo, Faltante
    FROM dbo.vw_InventarioBajoMinimo
    ORDER BY Faltante DESC, Nombre;
END
GO

/* Conciliación: la existencia debe ser igual a la suma de los movimientos. */
CREATE OR ALTER PROCEDURE dbo.usp_Inventario_Conciliacion
    @SoloDiferencias BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.ProductoId, p.SKU, p.Nombre, i.Existencia,
           ISNULL(s.Entradas, 0) AS Entradas, ISNULL(s.Salidas, 0) AS Salidas, ISNULL(s.Ajustes, 0) AS Ajustes,
           ISNULL(s.Saldo, 0) AS SaldoMovimientos, i.Existencia - ISNULL(s.Saldo, 0) AS Diferencia
    FROM dbo.Producto p
    JOIN dbo.Inventario i ON i.ProductoId = p.ProductoId
    LEFT JOIN (SELECT ProductoId,
                      SUM(CASE WHEN Tipo = 'ENTRADA' THEN Cantidad ELSE 0 END) AS Entradas,
                      SUM(CASE WHEN Tipo = 'SALIDA' THEN -Cantidad ELSE 0 END) AS Salidas,
                      SUM(CASE WHEN Tipo = 'AJUSTE' THEN Cantidad ELSE 0 END) AS Ajustes,
                      SUM(Cantidad) AS Saldo
               FROM dbo.MovimientoInventario GROUP BY ProductoId) s ON s.ProductoId = p.ProductoId
    WHERE ISNULL(@SoloDiferencias, 0) = 0 OR i.Existencia <> ISNULL(s.Saldo, 0)
    ORDER BY p.Nombre;
END
GO

/* =====================================================================
   RESEÑAS
   Regla: una reseña por cliente y producto, y solo si el cliente recibió
   el producto (pedido Entregado). La duplicidad la garantiza además la
   restricción UQ_Resena_Cliente_Producto.
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_Resena_Crear
    @ClienteId    INT,
    @ProductoId   INT,
    @Calificacion TINYINT,
    @Comentario   NVARCHAR(500) = NULL,
    @ResenaId     INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @Calificacion IS NULL OR @Calificacion NOT BETWEEN 1 AND 5
        THROW 51000, N'La calificación debe estar entre 1 y 5.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Producto WHERE ProductoId = @ProductoId)
        THROW 51001, N'El producto no existe.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Pedido o JOIN dbo.DetallePedido d ON d.PedidoId = o.PedidoId
                   WHERE o.ClienteId = @ClienteId AND d.ProductoId = @ProductoId AND o.EstadoId = 5)
        THROW 51006, N'Solo puede reseñar productos que haya comprado y recibido.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Resena WHERE ClienteId = @ClienteId AND ProductoId = @ProductoId AND Activo = 1)
        THROW 51002, N'Ya escribió una reseña para este producto; puede editarla.', 1;

    /* Si había una reseña eliminada lógicamente, se reactiva con el contenido nuevo. */
    UPDATE dbo.Resena
    SET Calificacion = @Calificacion, Comentario = NULLIF(LTRIM(RTRIM(@Comentario)), N''), Fecha = SYSDATETIME(), Activo = 1,
        @ResenaId = ResenaId
    WHERE ClienteId = @ClienteId AND ProductoId = @ProductoId;

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO dbo.Resena (ClienteId, ProductoId, Calificacion, Comentario)
        VALUES (@ClienteId, @ProductoId, @Calificacion, NULLIF(LTRIM(RTRIM(@Comentario)), N''));
        SET @ResenaId = SCOPE_IDENTITY();
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Resena_Actualizar
    @ResenaId     INT,
    @ClienteId    INT,
    @Calificacion TINYINT,
    @Comentario   NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Calificacion IS NULL OR @Calificacion NOT BETWEEN 1 AND 5
        THROW 51000, N'La calificación debe estar entre 1 y 5.', 1;
    UPDATE dbo.Resena
    SET Calificacion = @Calificacion, Comentario = NULLIF(LTRIM(RTRIM(@Comentario)), N''), Fecha = SYSDATETIME()
    WHERE ResenaId = @ResenaId AND ClienteId = @ClienteId AND Activo = 1;
    IF @@ROWCOUNT = 0 THROW 51001, N'La reseña no existe o no le pertenece.', 1;
END
GO

/* Eliminación lógica. La puede hacer el autor o un administrador. */
CREATE OR ALTER PROCEDURE dbo.usp_Resena_Eliminar
    @ResenaId  INT,
    @UsuarioId INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE r SET Activo = 0
    FROM dbo.Resena r
    JOIN dbo.Cliente c ON c.ClienteId = r.ClienteId
    WHERE r.ResenaId = @ResenaId AND r.Activo = 1
      AND (c.UsuarioId = @UsuarioId
           OR EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.UsuarioId = @UsuarioId AND u.RolId = 1 AND u.Activo = 1));
    IF @@ROWCOUNT = 0 THROW 51001, N'La reseña no existe o no tiene permiso para eliminarla.', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Resena_ListarPorProducto
    @ProductoId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.ResenaId, r.ClienteId, c.Nombre + N' ' + LEFT(c.Apellidos, 1) + N'.' AS Cliente,
           r.Calificacion, r.Comentario, r.Fecha
    FROM dbo.Resena r JOIN dbo.Cliente c ON c.ClienteId = r.ClienteId
    WHERE r.ProductoId = @ProductoId AND r.Activo = 1
    ORDER BY r.Fecha DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Resena_ListarPorCliente
    @ClienteId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.ResenaId, r.ProductoId, p.Nombre AS Producto, r.Calificacion, r.Comentario, r.Fecha
    FROM dbo.Resena r JOIN dbo.Producto p ON p.ProductoId = r.ProductoId
    WHERE r.ClienteId = @ClienteId AND r.Activo = 1
    ORDER BY r.Fecha DESC;
END
GO

/* Indica a la interfaz si el cliente puede reseñar el producto y si ya lo hizo. */
CREATE OR ALTER PROCEDURE dbo.usp_Resena_Estado
    @ClienteId  INT,
    @ProductoId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM dbo.Pedido o JOIN dbo.DetallePedido d ON d.PedidoId = o.PedidoId
                                  WHERE o.ClienteId = @ClienteId AND d.ProductoId = @ProductoId AND o.EstadoId = 5)
                     THEN 1 ELSE 0 END AS BIT) AS ComproYRecibio,
           (SELECT ResenaId FROM dbo.Resena WHERE ClienteId = @ClienteId AND ProductoId = @ProductoId AND Activo = 1) AS ResenaId,
           (SELECT Calificacion FROM dbo.Resena WHERE ClienteId = @ClienteId AND ProductoId = @ProductoId AND Activo = 1) AS Calificacion,
           (SELECT Comentario FROM dbo.Resena WHERE ClienteId = @ClienteId AND ProductoId = @ProductoId AND Activo = 1) AS Comentario;
END
GO

/* =====================================================================
   AUDITORÍA Y PANEL
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_Auditoria_Precios
    @ProductoId INT = NULL,
    @Desde      DATE = NULL,
    @Hasta      DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (500) a.AuditoriaId, a.Fecha, p.SKU, p.Nombre AS Producto, a.PrecioAnterior, a.PrecioNuevo,
           a.PrecioNuevo - a.PrecioAnterior AS Diferencia, u.Correo AS Usuario, a.UsuarioBD
    FROM dbo.AuditoriaPrecio a
    JOIN dbo.Producto p ON p.ProductoId = a.ProductoId
    LEFT JOIN dbo.Usuario u ON u.UsuarioId = a.UsuarioId
    WHERE (@ProductoId IS NULL OR a.ProductoId = @ProductoId)
      AND (@Desde IS NULL OR a.Fecha >= @Desde)
      AND (@Hasta IS NULL OR a.Fecha < DATEADD(DAY, 1, @Hasta))
    ORDER BY a.Fecha DESC, a.AuditoriaId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Auditoria_Estados
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (500) h.HistorialId, h.Fecha, h.PedidoId, ea.Nombre AS EstadoAnterior, en.Nombre AS EstadoNuevo,
           u.Correo AS Usuario, h.UsuarioBD, h.Comentario
    FROM dbo.HistorialEstadoPedido h
    LEFT JOIN dbo.EstadoPedido ea ON ea.EstadoId = h.EstadoAnteriorId
    JOIN dbo.EstadoPedido en ON en.EstadoId = h.EstadoNuevoId
    LEFT JOIN dbo.Usuario u ON u.UsuarioId = h.UsuarioId
    WHERE (@Desde IS NULL OR h.Fecha >= @Desde)
      AND (@Hasta IS NULL OR h.Fecha < DATEADD(DAY, 1, @Hasta))
    ORDER BY h.Fecha DESC, h.HistorialId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_Resumen
AS
BEGIN
    SET NOCOUNT ON;
    SELECT VentasTotales, PedidosVendidos, TicketPromedio, PedidosPendientes, PedidosEnProceso, PedidosCancelados,
           ClientesActivos, ProductosActivos, ProductosBajoMinimo, PromocionesVigentes
    FROM dbo.vw_ResumenComercial;
END
GO
PRINT '03_procedimientos.sql: función y procedimientos creados.';
GO
