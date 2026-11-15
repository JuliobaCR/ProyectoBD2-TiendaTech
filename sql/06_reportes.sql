/* =====================================================================
   06_reportes.sql  -  Consultas analíticas R1 a R10 (como procedimientos)
   Reglas comunes (están en la vista vw_VentasDetalle):
     - Un pedido cancelado NO cuenta como venta.
     - El importe es el histórico del detalle del pedido (TotalLinea),
       no el precio actual del catálogo. El envío no es venta de producto.
     - Rangos de fecha inclusivos; NULL significa "sin límite".

   Técnicas exigidas y dónde están:
     HAVING ............................ R1
     Subconsulta / NOT EXISTS .......... R8
     Función de ventana ................ R5 (RANK), R9 (LAG), R1 (ROW_NUMBER)
     Varias tablas con agrupación ...... R1, R5, R7 (vista de 6 tablas)
     Estructura matricial .............. R2 (PIVOT), R3 (agregación condicional)
   ===================================================================== */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE TiendaTechDB;
GO

/* ---------------------------------------------------------------------
   R1. Top N clientes (por defecto 5): monto comprado, cantidad de pedidos
       y número de productos diferentes adquiridos.
       HAVING filtra los grupos por cantidad mínima de pedidos.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_R1_TopClientes
    @Desde      DATE = NULL,
    @Hasta      DATE = NULL,
    @Top        INT = 5,
    @MinPedidos INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    IF ISNULL(@Top, 0) <= 0 SET @Top = 5;
    SELECT TOP (@Top)
           ROW_NUMBER() OVER (ORDER BY SUM(v.Importe) DESC, v.ClienteId) AS Posicion,
           v.ClienteId, v.Cliente,
           SUM(v.Importe) AS MontoComprado,
           COUNT(DISTINCT v.PedidoId) AS Pedidos,
           COUNT(DISTINCT v.ProductoId) AS ProductosDiferentes
    FROM dbo.vw_VentasDetalle v
    WHERE (@Desde IS NULL OR v.FechaPedido >= @Desde)
      AND (@Hasta IS NULL OR v.FechaPedido < DATEADD(DAY, 1, @Hasta))
    GROUP BY v.ClienteId, v.Cliente
    HAVING COUNT(DISTINCT v.PedidoId) >= ISNULL(@MinPedidos, 1)
    ORDER BY MontoComprado DESC, v.ClienteId;
END
GO

/* ---------------------------------------------------------------------
   R2. Matriz cliente x categoría: total comprado por cada cliente (fila)
       en cada categoría (columna), con PIVOT.
       Las columnas son las categorías que existan en la tabla, por eso la
       lista de columnas se arma en tiempo de ejecución. NO se concatena
       ninguna entrada del usuario: los nombres salen de dbo.Categoria y pasan
       por QUOTENAME, y las fechas viajan como parámetros de sp_executesql.
       EXECUTE AS OWNER: el SQL interno necesita leer la vista y el usuario de
       la aplicación solo tiene permiso de ejecutar procedimientos.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_R2_MatrizClienteCategoria
    @Desde DATE = NULL,
    @Hasta DATE = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Columnas NVARCHAR(MAX), @Seleccion NVARCHAR(MAX), @Total NVARCHAR(MAX), @Sql NVARCHAR(MAX);

    SELECT @Columnas  = STRING_AGG(CAST(QUOTENAME(Nombre) AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY Nombre),
           @Seleccion = STRING_AGG(CAST(N'ISNULL(' + QUOTENAME(Nombre) + N', 0) AS ' + QUOTENAME(Nombre) AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY Nombre),
           @Total     = STRING_AGG(CAST(N'ISNULL(' + QUOTENAME(Nombre) + N', 0)' AS NVARCHAR(MAX)), N' + ') WITHIN GROUP (ORDER BY Nombre)
    FROM dbo.Categoria;

    SET @Sql = N'
        SELECT pv.ClienteId, pv.Cliente, ' + @Seleccion + N', ' + @Total + N' AS Total
        FROM (SELECT v.ClienteId, v.Cliente, v.Categoria, v.Importe
              FROM dbo.vw_VentasDetalle v
              WHERE (@Desde IS NULL OR v.FechaPedido >= @Desde)
                AND (@Hasta IS NULL OR v.FechaPedido < DATEADD(DAY, 1, @Hasta))) f
        PIVOT (SUM(f.Importe) FOR f.Categoria IN (' + @Columnas + N')) pv
        ORDER BY Total DESC, pv.ClienteId;';

    EXEC sys.sp_executesql @Sql, N'@Desde DATE, @Hasta DATE', @Desde = @Desde, @Hasta = @Hasta;
END
GO

/* R2 en formato largo (cliente, categoría, total): sirve para verificar la matriz. */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_R2_ClienteCategoriaDetalle
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.ClienteId, v.Cliente, v.Categoria, SUM(v.Importe) AS Total, SUM(v.Cantidad) AS Unidades
    FROM dbo.vw_VentasDetalle v
    WHERE (@Desde IS NULL OR v.FechaPedido >= @Desde)
      AND (@Hasta IS NULL OR v.FechaPedido < DATEADD(DAY, 1, @Hasta))
    GROUP BY v.ClienteId, v.Cliente, v.Categoria
    ORDER BY v.Cliente, v.Categoria;
END
GO

/* ---------------------------------------------------------------------
   R3. Ventas mensuales por marca para el año seleccionado.
       Matriz marca x mes con agregación condicional. Las doce columnas
       siempre aparecen, así que los meses sin ventas se ven en 0; el
       LEFT JOIN conserva también las marcas que no vendieron nada.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_R3_VentasMensualesPorMarca
    @Anio INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Anio = ISNULL(@Anio, YEAR(SYSDATETIME()));
    SELECT m.Nombre AS Marca,
           ISNULL(SUM(CASE WHEN v.Mes =  1 THEN v.Importe END), 0) AS Ene,
           ISNULL(SUM(CASE WHEN v.Mes =  2 THEN v.Importe END), 0) AS Feb,
           ISNULL(SUM(CASE WHEN v.Mes =  3 THEN v.Importe END), 0) AS Mar,
           ISNULL(SUM(CASE WHEN v.Mes =  4 THEN v.Importe END), 0) AS Abr,
           ISNULL(SUM(CASE WHEN v.Mes =  5 THEN v.Importe END), 0) AS May,
           ISNULL(SUM(CASE WHEN v.Mes =  6 THEN v.Importe END), 0) AS Jun,
           ISNULL(SUM(CASE WHEN v.Mes =  7 THEN v.Importe END), 0) AS Jul,
           ISNULL(SUM(CASE WHEN v.Mes =  8 THEN v.Importe END), 0) AS Ago,
           ISNULL(SUM(CASE WHEN v.Mes =  9 THEN v.Importe END), 0) AS Sep,
           ISNULL(SUM(CASE WHEN v.Mes = 10 THEN v.Importe END), 0) AS Oct,
           ISNULL(SUM(CASE WHEN v.Mes = 11 THEN v.Importe END), 0) AS Nov,
           ISNULL(SUM(CASE WHEN v.Mes = 12 THEN v.Importe END), 0) AS Dic,
           ISNULL(SUM(v.Importe), 0) AS Total
    FROM dbo.Marca m
    LEFT JOIN dbo.vw_VentasDetalle v ON v.MarcaId = m.MarcaId AND v.Anio = @Anio
    GROUP BY m.MarcaId, m.Nombre
    ORDER BY Total DESC, m.Nombre;
END
GO

/* ---------------------------------------------------------------------
   R4. Evolución mensual: ventas, cantidad de pedidos y ticket promedio.
       El calendario de 12 meses con LEFT JOIN muestra los meses sin ventas.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_R4_EvolucionMensual
    @Anio INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Anio = ISNULL(@Anio, YEAR(SYSDATETIME()));
    WITH Meses AS (
        SELECT n AS Mes FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12)) x(n)
    ),
    Ventas AS (
        SELECT v.Mes, SUM(v.Importe) AS Ventas, COUNT(DISTINCT v.PedidoId) AS Pedidos
        FROM dbo.vw_VentasDetalle v
        WHERE v.Anio = @Anio
        GROUP BY v.Mes
    )
    SELECT m.Mes,
           CHOOSE(m.Mes, N'Enero', N'Febrero', N'Marzo', N'Abril', N'Mayo', N'Junio', N'Julio',
                         N'Agosto', N'Septiembre', N'Octubre', N'Noviembre', N'Diciembre') AS NombreMes,
           ISNULL(v.Ventas, 0) AS Ventas,
           ISNULL(v.Pedidos, 0) AS Pedidos,
           CAST(ISNULL(v.Ventas / NULLIF(v.Pedidos, 0), 0) AS DECIMAL(14,2)) AS TicketPromedio
    FROM Meses m
    LEFT JOIN Ventas v ON v.Mes = m.Mes
    ORDER BY m.Mes;
END
GO

/* ---------------------------------------------------------------------
   R5. Productos más vendidos: top N (10) por unidades o por ingresos,
       con su categoría y marca. Muestra la posición en ambos criterios.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_R5_ProductosMasVendidos
    @Desde    DATE = NULL,
    @Hasta    DATE = NULL,
    @Criterio CHAR(1) = 'U',     -- U = unidades, I = ingresos
    @Top      INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    IF ISNULL(@Top, 0) <= 0 SET @Top = 10;
    IF @Criterio NOT IN ('U', 'I') THROW 51000, N'El criterio debe ser U (unidades) o I (ingresos).', 1;

    WITH Ventas AS (
        SELECT v.ProductoId, v.SKU, v.Producto, v.Categoria, v.Marca,
               SUM(v.Cantidad) AS Unidades, SUM(v.Importe) AS Ingresos,
               RANK() OVER (ORDER BY SUM(v.Cantidad) DESC) AS PosicionUnidades,
               RANK() OVER (ORDER BY SUM(v.Importe) DESC) AS PosicionIngresos
        FROM dbo.vw_VentasDetalle v
        WHERE (@Desde IS NULL OR v.FechaPedido >= @Desde)
          AND (@Hasta IS NULL OR v.FechaPedido < DATEADD(DAY, 1, @Hasta))
        GROUP BY v.ProductoId, v.SKU, v.Producto, v.Categoria, v.Marca
    )
    SELECT TOP (@Top) SKU, Producto, Categoria, Marca, Unidades, Ingresos, PosicionUnidades, PosicionIngresos
    FROM Ventas
    ORDER BY CASE WHEN @Criterio = 'U' THEN PosicionUnidades ELSE PosicionIngresos END,
             CASE WHEN @Criterio = 'U' THEN PosicionIngresos ELSE PosicionUnidades END, Producto;
END
GO

/* ---------------------------------------------------------------------
   R6. Inventario crítico: productos bajo mínimo, existencia actual,
       unidades faltantes y estimación de reposición.
       Estimación: reponer hasta el doble del mínimo; se valora al costo
       vigente. Con la venta diaria promedio del período se estiman los
       días de cobertura que quedan.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_R6_InventarioCritico
    @DiasAnalisis INT = 90
AS
BEGIN
    SET NOCOUNT ON;
    IF ISNULL(@DiasAnalisis, 0) <= 0 SET @DiasAnalisis = 90;
    DECLARE @Desde DATE = DATEADD(DAY, -@DiasAnalisis, CAST(SYSDATETIME() AS DATE));

    SELECT b.SKU, b.Nombre AS Producto, b.Marca, b.Categoria,
           b.Existencia, b.StockMinimo, b.Faltante AS UnidadesFaltantes,
           ISNULL(s.Unidades, 0) AS VendidasEnPeriodo,
           CAST(ISNULL(s.Unidades, 0) * 1.0 / @DiasAnalisis AS DECIMAL(10,2)) AS VentaDiariaPromedio,
           CAST(b.Existencia / NULLIF(ISNULL(s.Unidades, 0) * 1.0 / @DiasAnalisis, 0) AS DECIMAL(10,1)) AS DiasDeCobertura,
           2 * b.StockMinimo - b.Existencia AS UnidadesAReponer,
           CAST((2 * b.StockMinimo - b.Existencia) * b.Costo AS DECIMAL(14,2)) AS CostoEstimadoReposicion
    FROM dbo.vw_InventarioBajoMinimo b
    LEFT JOIN (SELECT ProductoId, SUM(Cantidad) AS Unidades
               FROM dbo.vw_VentasDetalle WHERE FechaPedido >= @Desde
               GROUP BY ProductoId) s ON s.ProductoId = b.ProductoId
    ORDER BY b.Faltante DESC, b.Nombre;
END
GO

/* ---------------------------------------------------------------------
   R7. Rentabilidad por producto o por categoría.
       Ingresos = lo vendido; Costo = costo histórico guardado en el detalle;
       Utilidad bruta = Ingresos - Costo (utilidad NO es lo mismo que ventas).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_R7_Rentabilidad
    @AgruparPor CHAR(1) = 'P',    -- P = producto, C = categoría
    @Desde      DATE = NULL,
    @Hasta      DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AgruparPor NOT IN ('P', 'C') THROW 51000, N'Agrupar por P (producto) o C (categoría).', 1;

    IF @AgruparPor = 'C'
        SELECT v.Categoria,
               SUM(v.Cantidad) AS Unidades,
               SUM(v.Importe) AS Ingresos,
               SUM(v.CostoTotal) AS CostoHistorico,
               SUM(v.Importe) - SUM(v.CostoTotal) AS UtilidadBruta,
               CAST((SUM(v.Importe) - SUM(v.CostoTotal)) * 100.0 / NULLIF(SUM(v.Importe), 0) AS DECIMAL(6,2)) AS MargenPorcentaje
        FROM dbo.vw_VentasDetalle v
        WHERE (@Desde IS NULL OR v.FechaPedido >= @Desde)
          AND (@Hasta IS NULL OR v.FechaPedido < DATEADD(DAY, 1, @Hasta))
        GROUP BY v.CategoriaId, v.Categoria
        ORDER BY UtilidadBruta DESC;
    ELSE
        SELECT v.SKU, v.Producto, v.Categoria,
               SUM(v.Cantidad) AS Unidades,
               SUM(v.Importe) AS Ingresos,
               SUM(v.CostoTotal) AS CostoHistorico,
               SUM(v.Importe) - SUM(v.CostoTotal) AS UtilidadBruta,
               CAST((SUM(v.Importe) - SUM(v.CostoTotal)) * 100.0 / NULLIF(SUM(v.Importe), 0) AS DECIMAL(6,2)) AS MargenPorcentaje
        FROM dbo.vw_VentasDetalle v
        WHERE (@Desde IS NULL OR v.FechaPedido >= @Desde)
          AND (@Hasta IS NULL OR v.FechaPedido < DATEADD(DAY, 1, @Hasta))
        GROUP BY v.ProductoId, v.SKU, v.Producto, v.Categoria
        ORDER BY UtilidadBruta DESC;
END
GO

/* ---------------------------------------------------------------------
   R8. Clientes sin compras: nunca han comprado, o no compraron en el
       rango de fechas indicado. Usa NOT EXISTS (subconsulta correlacionada).
       Un pedido cancelado no cuenta como compra.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_R8_ClientesSinCompras
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.ClienteId, c.Nombre + N' ' + c.Apellidos AS Cliente, u.Correo, c.Telefono, c.FechaRegistro,
           uc.UltimaCompra,
           CASE WHEN uc.UltimaCompra IS NULL THEN N'Nunca ha comprado' ELSE N'Sin compras en el período' END AS Situacion
    FROM dbo.Cliente c
    JOIN dbo.Usuario u ON u.UsuarioId = c.UsuarioId
    OUTER APPLY (SELECT MAX(o.FechaPedido) AS UltimaCompra
                 FROM dbo.Pedido o WHERE o.ClienteId = c.ClienteId AND o.EstadoId <> 6) uc
    WHERE c.Activo = 1
      AND NOT EXISTS (SELECT 1
                      FROM dbo.Pedido o
                      WHERE o.ClienteId = c.ClienteId
                        AND o.EstadoId <> 6
                        AND (@Desde IS NULL OR o.FechaPedido >= @Desde)
                        AND (@Hasta IS NULL OR o.FechaPedido < DATEADD(DAY, 1, @Hasta)))
    ORDER BY uc.UltimaCompra, Cliente;
END
GO

/* ---------------------------------------------------------------------
   R9. Comparación temporal: ventas de cada mes y su variación absoluta y
       porcentual respecto del mes anterior, con LAG.
       El calendario empieza en diciembre del año anterior para que enero
       también tenga contra qué compararse.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_R9_ComparacionMensual
    @Anio INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Anio = ISNULL(@Anio, YEAR(SYSDATETIME()));
    WITH Calendario AS (
        SELECT DATEFROMPARTS(@Anio - 1, 12, 1) AS InicioMes
        UNION ALL
        SELECT DATEFROMPARTS(@Anio, n, 1) FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12)) x(n)
    ),
    VentasMes AS (
        SELECT c.InicioMes, ISNULL(SUM(v.Importe), 0) AS Ventas
        FROM Calendario c
        LEFT JOIN dbo.vw_VentasDetalle v ON v.Anio = YEAR(c.InicioMes) AND v.Mes = MONTH(c.InicioMes)
        GROUP BY c.InicioMes
    ),
    Comparado AS (
        SELECT InicioMes, Ventas, LAG(Ventas) OVER (ORDER BY InicioMes) AS VentasMesAnterior
        FROM VentasMes
    )
    SELECT MONTH(InicioMes) AS Mes,
           CHOOSE(MONTH(InicioMes), N'Enero', N'Febrero', N'Marzo', N'Abril', N'Mayo', N'Junio', N'Julio',
                                    N'Agosto', N'Septiembre', N'Octubre', N'Noviembre', N'Diciembre') AS NombreMes,
           Ventas, VentasMesAnterior,
           Ventas - VentasMesAnterior AS VariacionAbsoluta,
           CAST((Ventas - VentasMesAnterior) * 100.0 / NULLIF(VentasMesAnterior, 0) AS DECIMAL(9,2)) AS VariacionPorcentual
    FROM Comparado
    WHERE YEAR(InicioMes) = @Anio
    ORDER BY InicioMes;
END
GO

/* ---------------------------------------------------------------------
   R10. Resumen de pedidos con filtros parametrizados: estado, cliente,
        rango de fechas y texto. Incluye todos los estados (también los
        cancelados, porque es un listado operativo y no un reporte de ventas).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_R10_ResumenPedidos
    @EstadoId  TINYINT = NULL,
    @ClienteId INT = NULL,
    @Desde     DATE = NULL,
    @Hasta     DATE = NULL,
    @Buscar    NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Buscar = NULLIF(LTRIM(RTRIM(@Buscar)), N'');
    SELECT v.PedidoId, v.FechaPedido, v.Estado, v.Cliente, v.Correo, v.Lineas, v.Unidades,
           v.Subtotal, v.DescuentoTotal, v.CostoEnvio, v.Total
    FROM dbo.vw_ResumenPedidos v
    WHERE (@EstadoId IS NULL OR v.EstadoId = @EstadoId)
      AND (@ClienteId IS NULL OR v.ClienteId = @ClienteId)
      AND (@Desde IS NULL OR v.FechaPedido >= @Desde)
      AND (@Hasta IS NULL OR v.FechaPedido < DATEADD(DAY, 1, @Hasta))
      AND (@Buscar IS NULL OR v.Cliente LIKE N'%' + @Buscar + N'%' OR v.Correo LIKE N'%' + @Buscar + N'%')
    ORDER BY v.FechaPedido DESC, v.PedidoId DESC;
END
GO

/* Cantidad y monto de pedidos por estado (encabezado del panel de R10). */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_R10_PedidosPorEstado
    @Desde DATE = NULL,
    @Hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT e.EstadoId, e.Nombre AS Estado, COUNT(o.PedidoId) AS Pedidos, ISNULL(SUM(o.Total), 0) AS MontoTotal
    FROM dbo.EstadoPedido e
    LEFT JOIN dbo.Pedido o ON o.EstadoId = e.EstadoId
         AND (@Desde IS NULL OR o.FechaPedido >= @Desde)
         AND (@Hasta IS NULL OR o.FechaPedido < DATEADD(DAY, 1, @Hasta))
    GROUP BY e.EstadoId, e.Nombre
    ORDER BY e.EstadoId;
END
GO
PRINT '06_reportes.sql: reportes R1-R10 creados.';
GO

/* =====================================================================
   Ejemplos de ejecución (para la defensa, desde SSMS):

   EXEC dbo.usp_Reporte_R1_TopClientes @Desde = '2026-01-01', @Hasta = '2026-12-31';
   EXEC dbo.usp_Reporte_R2_MatrizClienteCategoria;
   EXEC dbo.usp_Reporte_R3_VentasMensualesPorMarca @Anio = 2026;
   EXEC dbo.usp_Reporte_R4_EvolucionMensual @Anio = 2026;
   EXEC dbo.usp_Reporte_R5_ProductosMasVendidos @Criterio = 'U';
   EXEC dbo.usp_Reporte_R5_ProductosMasVendidos @Criterio = 'I';
   EXEC dbo.usp_Reporte_R6_InventarioCritico;
   EXEC dbo.usp_Reporte_R7_Rentabilidad @AgruparPor = 'C';
   EXEC dbo.usp_Reporte_R8_ClientesSinCompras;
   EXEC dbo.usp_Reporte_R8_ClientesSinCompras @Desde = '2026-09-01', @Hasta = '2026-11-30';
   EXEC dbo.usp_Reporte_R9_ComparacionMensual @Anio = 2026;
   EXEC dbo.usp_Reporte_R10_ResumenPedidos @EstadoId = 5;
   ===================================================================== */
