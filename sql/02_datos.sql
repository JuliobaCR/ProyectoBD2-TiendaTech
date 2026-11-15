/* =====================================================================
   02_datos.sql  -  Datos de prueba reproducibles (todos ficticios)
   - Fechas fijas del año de evaluación (2026): cada ejecución produce
     exactamente los mismos datos.
   - Pedidos, pagos, envíos, historial, movimientos y existencias concilian
     (se verifica al final del script; si algo no cuadra, el script falla).
   Nota: este script se ejecuta ANTES de crear procedimientos y triggers,
   por eso inserta directamente y llena a mano el historial de estados.
   ===================================================================== */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO
USE TiendaTechDB;
GO
BEGIN TRANSACTION;

/* ---------------- Catálogos fijos ---------------- */
INSERT INTO dbo.Rol (RolId, Nombre) VALUES (1, N'Administrador'), (2, N'Cliente');

INSERT INTO dbo.EstadoPedido (EstadoId, Nombre, EsFinal) VALUES
 (1, N'Pendiente', 0), (2, N'Confirmado', 0), (3, N'En preparación', 0),
 (4, N'Enviado', 0),   (5, N'Entregado', 1),  (6, N'Cancelado', 1);

/* Transiciones válidas. La cancelación solo es posible antes del envío. */
INSERT INTO dbo.TransicionEstado (EstadoOrigenId, EstadoDestinoId) VALUES
 (1,2), (1,6),      -- Pendiente      -> Confirmado | Cancelado
 (2,3), (2,6),      -- Confirmado     -> En preparación | Cancelado
 (3,4), (3,6),      -- En preparación -> Enviado | Cancelado
 (4,5);             -- Enviado        -> Entregado

INSERT INTO dbo.MetodoPago (Nombre, AprobacionInmediata) VALUES
 (N'Tarjeta de crédito', 1), (N'Tarjeta de débito', 1),
 (N'SINPE Móvil', 0),        (N'Transferencia bancaria', 0);

INSERT INTO dbo.ZonaEnvio (Nombre, Tarifa, DiasEstimados) VALUES
 (N'Gran Área Metropolitana', 2500, 2),
 (N'Zona Norte', 4000, 4),
 (N'Pacífico Norte y Central', 4500, 4),
 (N'Caribe', 4500, 5),
 (N'Zona Sur', 5000, 6);

/* ---------------- Marcas (10) y categorías (10) ---------------- */
INSERT INTO dbo.Marca (Nombre, PaisOrigen) VALUES
 (N'Apple', N'Estados Unidos'), (N'Samsung', N'Corea del Sur'), (N'Lenovo', N'China'),
 (N'HP', N'Estados Unidos'),    (N'Dell', N'Estados Unidos'),   (N'Asus', N'Taiwán'),
 (N'Logitech', N'Suiza'),       (N'Sony', N'Japón'),            (N'Xiaomi', N'China'),
 (N'Kingston', N'Estados Unidos');

INSERT INTO dbo.Categoria (Nombre, Descripcion) VALUES
 (N'Laptops', N'Computadoras portátiles para estudio, trabajo y juegos'),
 (N'Celulares', N'Teléfonos inteligentes'),
 (N'Tablets', N'Tabletas y lectores'),
 (N'Monitores', N'Pantallas para escritorio'),
 (N'Teclados', N'Teclados de membrana y mecánicos'),
 (N'Mouse', N'Ratones alámbricos e inalámbricos'),
 (N'Audio', N'Audífonos y auriculares'),
 (N'Almacenamiento', N'Discos SSD, memorias USB y tarjetas'),
 (N'Relojes inteligentes', N'Relojes y bandas de actividad'),
 (N'Accesorios', N'Cargadores, cámaras, bases y más');

/* ---------------- Productos (55) ---------------- */
DECLARE @P TABLE (Ord INT, SKU VARCHAR(20), Nombre NVARCHAR(120), Marca NVARCHAR(60), Categoria NVARCHAR(60),
                  Precio DECIMAL(12,2), Costo DECIMAL(12,2), Destacado BIT, Specs NVARCHAR(1000));
INSERT INTO @P VALUES
 ( 1,'LAP-001',N'MacBook Air 13" M3',            N'Apple',   N'Laptops', 720000, 610000, 1, N'Chip M3; 8 GB RAM; SSD 256 GB; pantalla Liquid Retina 13.6"'),
 ( 2,'LAP-002',N'Lenovo IdeaPad Slim 5',         N'Lenovo',  N'Laptops', 420000, 340000, 0, N'Ryzen 5 7530U; 16 GB RAM; SSD 512 GB; 15.6" FHD'),
 ( 3,'LAP-003',N'HP Pavilion 15',                N'HP',      N'Laptops', 395000, 320000, 0, N'Core i5-1335U; 8 GB RAM; SSD 512 GB; 15.6" FHD'),
 ( 4,'LAP-004',N'Dell Inspiron 14',              N'Dell',    N'Laptops', 410000, 335000, 0, N'Core i5-1334U; 16 GB RAM; SSD 512 GB; 14" FHD+'),
 ( 5,'LAP-005',N'Asus TUF Gaming F15',           N'Asus',    N'Laptops', 650000, 540000, 1, N'Core i7-12700H; RTX 4060; 16 GB RAM; SSD 1 TB; 144 Hz'),
 ( 6,'LAP-006',N'Lenovo ThinkPad E14',           N'Lenovo',  N'Laptops', 560000, 465000, 0, N'Core i7-1355U; 16 GB RAM; SSD 512 GB; 14" WUXGA'),
 ( 7,'LAP-007',N'Asus Vivobook 15',              N'Asus',    N'Laptops', 330000, 270000, 0, N'Core i3-1215U; 8 GB RAM; SSD 256 GB; 15.6" FHD'),
 ( 8,'CEL-001',N'iPhone 15 128 GB',              N'Apple',   N'Celulares', 560000, 480000, 1, N'Pantalla 6.1" OLED; chip A16; cámara 48 MP; USB-C'),
 ( 9,'CEL-002',N'Samsung Galaxy S24',            N'Samsung', N'Celulares', 520000, 430000, 1, N'Pantalla 6.2" AMOLED 120 Hz; 8 GB RAM; 256 GB'),
 (10,'CEL-003',N'Samsung Galaxy A55',            N'Samsung', N'Celulares', 235000, 185000, 0, N'Pantalla 6.6" AMOLED; 8 GB RAM; 128 GB; 5000 mAh'),
 (11,'CEL-004',N'Xiaomi Redmi Note 13',          N'Xiaomi',  N'Celulares', 145000, 110000, 0, N'Pantalla 6.67" AMOLED; 8 GB RAM; 256 GB; 108 MP'),
 (12,'CEL-005',N'Xiaomi 14T',                    N'Xiaomi',  N'Celulares', 340000, 275000, 0, N'Pantalla 6.67" 144 Hz; 12 GB RAM; 256 GB; óptica Leica'),
 (13,'CEL-006',N'Sony Xperia 10 VI',             N'Sony',    N'Celulares', 265000, 215000, 0, N'Pantalla 6.1" OLED 21:9; 8 GB RAM; 128 GB'),
 (14,'TAB-001',N'iPad 10.ª generación 64 GB',    N'Apple',   N'Tablets', 265000, 220000, 1, N'Pantalla 10.9"; chip A14; Wi-Fi; USB-C'),
 (15,'TAB-002',N'Samsung Galaxy Tab S9 FE',      N'Samsung', N'Tablets', 255000, 205000, 0, N'Pantalla 10.9" 90 Hz; 6 GB RAM; 128 GB; S Pen incluido'),
 (16,'TAB-003',N'Lenovo Tab M11',                N'Lenovo',  N'Tablets', 115000,  88000, 0, N'Pantalla 11" 90 Hz; 4 GB RAM; 128 GB'),
 (17,'TAB-004',N'Xiaomi Pad 6',                  N'Xiaomi',  N'Tablets', 185000, 148000, 0, N'Pantalla 11" 144 Hz; 8 GB RAM; 256 GB'),
 (18,'MON-001',N'Dell UltraSharp 27" U2724D',    N'Dell',    N'Monitores', 310000, 250000, 1, N'27" QHD IPS; 120 Hz; USB-C; 100 % sRGB'),
 (19,'MON-002',N'Samsung Odyssey G5 27"',        N'Samsung', N'Monitores', 215000, 170000, 0, N'27" QHD curvo; 165 Hz; 1 ms; FreeSync'),
 (20,'MON-003',N'HP M24f 24"',                   N'HP',      N'Monitores',  92000,  70000, 0, N'24" FHD IPS; 75 Hz; HDMI y VGA'),
 (21,'MON-004',N'Asus ProArt 24"',               N'Asus',    N'Monitores', 175000, 140000, 0, N'24" WUXGA IPS; calibrado de fábrica; USB hub'),
 (22,'MON-005',N'Lenovo L27i 27"',               N'Lenovo',  N'Monitores', 118000,  92000, 0, N'27" FHD IPS; 100 Hz; HDMI'),
 (23,'TEC-001',N'Logitech MX Keys S',            N'Logitech',N'Teclados',  68000,  50000, 1, N'Inalámbrico; retroiluminado; multi-dispositivo; USB-C'),
 (24,'TEC-002',N'Logitech G413 SE mecánico',     N'Logitech',N'Teclados',  45000,  33000, 0, N'Mecánico táctil; teclas PBT; retroiluminación blanca'),
 (25,'TEC-003',N'HP 350 Compact',                N'HP',      N'Teclados',  22000,  15000, 0, N'Bluetooth; compacto; hasta 3 dispositivos'),
 (26,'TEC-004',N'Asus ROG Strix Scope II',       N'Asus',    N'Teclados',  85000,  64000, 0, N'Mecánico; switches ROG NX; RGB; reposamuñecas'),
 (27,'TEC-005',N'Apple Magic Keyboard',          N'Apple',   N'Teclados',  72000,  56000, 0, N'Inalámbrico; recargable; distribución en español'),
 (28,'MOU-001',N'Logitech MX Master 3S',         N'Logitech',N'Mouse',     62000,  46000, 1, N'8000 DPI; clics silenciosos; rueda MagSpeed'),
 (29,'MOU-002',N'Logitech G502 X',               N'Logitech',N'Mouse',     48000,  35000, 0, N'Sensor HERO 25K; 13 controles programables'),
 (30,'MOU-003',N'HP Z3700 inalámbrico',          N'HP',      N'Mouse',     12500,   8000, 0, N'2.4 GHz; 1200 DPI; diseño delgado'),
 (31,'MOU-004',N'Dell MS3320W',                  N'Dell',    N'Mouse',     18500,  12500, 0, N'Bluetooth y 2.4 GHz; 1600 DPI'),
 (32,'MOU-005',N'Xiaomi Wireless Mouse Lite',    N'Xiaomi',  N'Mouse',      7500,   4800, 0, N'2.4 GHz; 1000 DPI; ambidiestro'),
 (33,'AUD-001',N'Sony WH-1000XM5',               N'Sony',    N'Audio',    215000, 170000, 1, N'Cancelación de ruido; 30 h de batería; Bluetooth 5.2'),
 (34,'AUD-002',N'Apple AirPods Pro 2',           N'Apple',   N'Audio',    155000, 125000, 1, N'Cancelación activa; estuche USB-C; audio espacial'),
 (35,'AUD-003',N'Samsung Galaxy Buds3',          N'Samsung', N'Audio',     89000,  68000, 0, N'Cancelación activa; IP57; 30 h con estuche'),
 (36,'AUD-004',N'Sony WF-C700N',                 N'Sony',    N'Audio',     62000,  46000, 0, N'Cancelación de ruido; 15 h con estuche; IPX4'),
 (37,'AUD-005',N'Xiaomi Redmi Buds 5',           N'Xiaomi',  N'Audio',     22000,  15000, 0, N'Cancelación 46 dB; 40 h con estuche'),
 (38,'AUD-006',N'Logitech G435',                 N'Logitech',N'Audio',     42000,  31000, 0, N'Diadema inalámbrica; Lightspeed y Bluetooth; 165 g'),
 (39,'ALM-001',N'Kingston NV2 1 TB NVMe',        N'Kingston',N'Almacenamiento', 42000, 31000, 0, N'M.2 2280 PCIe 4.0; hasta 3500 MB/s'),
 (40,'ALM-002',N'Kingston A400 480 GB SSD',      N'Kingston',N'Almacenamiento', 24000, 17000, 0, N'SATA 2.5"; hasta 500 MB/s'),
 (41,'ALM-003',N'Kingston DataTraveler 128 GB',  N'Kingston',N'Almacenamiento',  9500,  6000, 0, N'USB 3.2; cuerpo metálico'),
 (42,'ALM-004',N'Samsung T7 Portable 1 TB',      N'Samsung', N'Almacenamiento', 68000, 52000, 1, N'SSD externo USB 3.2; hasta 1050 MB/s'),
 (43,'ALM-005',N'Kingston Canvas microSD 256 GB',N'Kingston',N'Almacenamiento', 16500, 11000, 0, N'Clase 10 UHS-I; adaptador SD incluido'),
 (44,'ALM-006',N'Samsung 990 EVO 2 TB',          N'Samsung', N'Almacenamiento', 98000, 77000, 0, N'M.2 NVMe; hasta 5000 MB/s'),
 (45,'REL-001',N'Apple Watch SE 44 mm',          N'Apple',   N'Relojes inteligentes', 185000, 150000, 0, N'GPS; detección de caídas; resistencia al agua 50 m'),
 (46,'REL-002',N'Samsung Galaxy Watch7',         N'Samsung', N'Relojes inteligentes', 165000, 130000, 0, N'44 mm; sensor BioActive; Wear OS'),
 (47,'REL-003',N'Xiaomi Smart Band 9',           N'Xiaomi',  N'Relojes inteligentes',  28000,  19000, 0, N'AMOLED 1.62"; 21 días de batería; 5 ATM'),
 (48,'REL-004',N'Xiaomi Redmi Watch 5',          N'Xiaomi',  N'Relojes inteligentes',  58000,  43000, 0, N'AMOLED 2.07"; llamadas Bluetooth; GPS'),
 (49,'ACC-001',N'Logitech C920s webcam',         N'Logitech',N'Accesorios',  48000,  35000, 0, N'Full HD 1080p; tapa de privacidad; dos micrófonos'),
 (50,'ACC-002',N'Kingston Fury 16 GB DDR5',      N'Kingston',N'Accesorios',  46000,  34000, 0, N'DDR5 5600 MHz; CL40; disipador'),
 (51,'ACC-003',N'Apple cargador USB-C 20 W',     N'Apple',   N'Accesorios',  16500,  11000, 0, N'Carga rápida; compatible con iPhone y iPad'),
 (52,'ACC-004',N'Samsung cargador inalámbrico 15 W', N'Samsung', N'Accesorios', 24500, 17000, 0, N'Carga rápida Qi; ventilador integrado'),
 (53,'ACC-005',N'Dell base USB-C WD19S',         N'Dell',    N'Accesorios', 125000,  98000, 0, N'130 W; HDMI; 2 DisplayPort; Ethernet'),
 (54,'ACC-006',N'Lenovo mochila 15.6"',          N'Lenovo',  N'Accesorios',  21000,  14000, 0, N'Resistente al agua; compartimento acolchado'),
 (55,'ACC-007',N'Sony control DualSense',        N'Sony',    N'Accesorios',  46000,  36000, 0, N'Retroalimentación háptica; gatillos adaptativos');

INSERT INTO dbo.Producto (SKU, Nombre, Descripcion, Especificaciones, MarcaId, CategoriaId, Precio, Costo, Destacado, FechaCreacion)
SELECT p.SKU, p.Nombre, p.Nombre + N' de ' + p.Marca + N'. Garantía de 12 meses en TiendaTech.',
       p.Specs, m.MarcaId, c.CategoriaId, p.Precio, p.Costo, p.Destacado, '2025-12-10T09:00:00'
FROM @P p
JOIN dbo.Marca m ON m.Nombre = p.Marca
JOIN dbo.Categoria c ON c.Nombre = p.Categoria
ORDER BY p.Ord;

INSERT INTO dbo.ProductoImagen (ProductoId, Url, EsPrincipal, Orden)
SELECT ProductoId, N'/static/img/productos/' + SKU + N'.svg', 1, 1 FROM dbo.Producto ORDER BY ProductoId;

/* Inventario: existencia en 0; se calcula al final a partir de los movimientos. */
INSERT INTO dbo.Inventario (ProductoId, Existencia, StockMinimo, FechaActualizacion)
SELECT ProductoId, 0,
       CASE WHEN Precio >= 300000 THEN 4 WHEN Precio >= 100000 THEN 6 WHEN Precio >= 30000 THEN 8 ELSE 12 END,
       '2025-12-15T08:00:00'
FROM dbo.Producto;

/* ---------------- Usuarios y clientes (20) ----------------
   Las contraseñas de demostración están en el README; aquí solo va el hash
   scrypt generado con werkzeug.security (biblioteca estándar de Flask). */
DECLARE @HashAdmin   NVARCHAR(255) = N'scrypt:32768:8:1$AX95GA1Gk5v4BSOU$d8e0c5236d6b9605c624632b956699e0f8691f1c5d84372295cbd8d0ffb8931e658aa515627890baafd7d1164113db5860f98dc0c508064451c99b0b41efcb6d';
DECLARE @HashCliente NVARCHAR(255) = N'scrypt:32768:8:1$mhcxzLAOghmchvyR$3e9b9d46a7af4bf64b5e86f2a2279a5e2d5767b7a62f1463414b00b48d5c42d2d78ade97d609cd332f9bdb2627e338ca6c3a668ea26b9025a2764065c3f747cc';

INSERT INTO dbo.Usuario (Correo, HashContrasena, RolId, FechaCreacion)
VALUES (N'admin@tiendatech.test', @HashAdmin, 1, '2025-12-01T08:00:00');   -- UsuarioId = 1

DECLARE @C TABLE (Ord INT, Nombre NVARCHAR(60), Apellidos NVARCHAR(80), Provincia NVARCHAR(40), Canton NVARCHAR(60), Distrito NVARCHAR(60), Zona INT);
INSERT INTO @C VALUES
 ( 1,N'Andrea',  N'Solano Vega',      N'San José',  N'Escazú',        N'San Rafael',   1),
 ( 2,N'Bryan',   N'Mora Quesada',     N'Alajuela',  N'San Carlos',    N'Quesada',      2),
 ( 3,N'Camila',  N'Rojas Chaves',     N'Guanacaste',N'Liberia',       N'Liberia',      3),
 ( 4,N'Daniel',  N'Vargas Solís',     N'Limón',     N'Pococí',        N'Guápiles',     4),
 ( 5,N'Elena',   N'Jiménez Arias',    N'Puntarenas',N'Golfito',       N'Golfito',      5),
 ( 6,N'Fabián',  N'Castro Méndez',    N'Heredia',   N'Heredia',       N'Mercedes',     1),
 ( 7,N'Gabriela',N'Araya Campos',     N'Alajuela',  N'Upala',         N'Upala',        2),
 ( 8,N'Héctor',  N'Navarro Leiva',    N'Puntarenas',N'Garabito',      N'Jacó',         3),
 ( 9,N'Irene',   N'Salazar Brenes',   N'Limón',     N'Limón',         N'Limón',        4),
 (10,N'Javier',  N'Cordero Ulate',    N'San José',  N'Pérez Zeledón', N'San Isidro',   5),
 (11,N'Karla',   N'Esquivel Monge',   N'Cartago',   N'Cartago',       N'Oriental',     1),
 (12,N'Luis',    N'Hidalgo Porras',   N'Alajuela',  N'Los Chiles',    N'Los Chiles',   2),
 (13,N'Mariana', N'Zúñiga Alfaro',    N'Guanacaste',N'Nicoya',        N'Nicoya',       3),
 (14,N'Nelson',  N'Barrantes Rivas',  N'Limón',     N'Siquirres',     N'Siquirres',    4),
 (15,N'Olga',    N'Fonseca Marín',    N'Puntarenas',N'Corredores',    N'Corredor',     5),
 (16,N'Pablo',   N'Granados Sibaja',  N'San José',  N'Curridabat',    N'Granadilla',   1),
 (17,N'Raquel',  N'Villalobos Acuña', N'Alajuela',  N'Guatuso',       N'San Rafael',   2),
 (18,N'Sergio',  N'Montero Badilla',  N'Guanacaste',N'Santa Cruz',    N'Tamarindo',    3),
 (19,N'Tatiana', N'Chacón Durán',     N'Limón',     N'Talamanca',     N'Cahuita',      4),
 (20,N'Ulises',  N'Pizarro Céspedes', N'San José',  N'Desamparados',  N'San Miguel',   1);

INSERT INTO dbo.Usuario (Correo, HashContrasena, RolId, FechaCreacion)
SELECT N'cliente' + RIGHT('0' + CAST(Ord AS VARCHAR(2)), 2) + N'@correo.test', @HashCliente, 2, '2025-12-20T10:00:00'
FROM @C ORDER BY Ord;                                                        -- UsuarioId = Ord + 1

INSERT INTO dbo.Cliente (UsuarioId, Nombre, Apellidos, Identificacion, Telefono, FechaRegistro)
SELECT Ord + 1, Nombre, Apellidos,
       CAST(1 + Ord % 7 AS VARCHAR(1)) + '-0' + CAST(100 + Ord * 37 AS VARCHAR(3)) + '-0' + CAST(200 + Ord * 29 AS VARCHAR(3)),
       '8' + CAST(8000000 + Ord * 104729 % 1000000 AS VARCHAR(7)),
       '2025-12-20T10:00:00'
FROM @C ORDER BY Ord;                                                        -- ClienteId = Ord

INSERT INTO dbo.Direccion (ClienteId, ZonaEnvioId, Alias, Provincia, Canton, Distrito, Detalle, Predeterminada)
SELECT Ord, Zona, N'Casa', Provincia, Canton, Distrito,
       N'De la iglesia ' + CAST(100 + Ord * 25 AS NVARCHAR(4)) + N' m al norte, casa #' + CAST(Ord AS NVARCHAR(2)), 1
FROM @C ORDER BY Ord;                                                        -- DireccionId = Ord
INSERT INTO dbo.Direccion (ClienteId, ZonaEnvioId, Alias, Provincia, Canton, Distrito, Detalle, Predeterminada)
VALUES (1, 1, N'Oficina', N'San José', N'San José', N'Mata Redonda', N'Edificio Torre Sabana, piso 4', 0),
       (6, 1, N'Trabajo', N'Heredia',  N'Belén',    N'La Asunción',  N'Zona franca, edificio B', 0);

/* ---------------- Promociones (5): 2 vencidas, 2 vigentes, 1 futura ---------------- */
INSERT INTO dbo.Promocion (Nombre, TipoDescuento, Valor, FechaInicio, FechaFin) VALUES
 (N'Regreso a clases',          'P', 15,   '2026-01-15', '2026-02-28'),   -- vencida
 (N'Semana Gamer',              'M', 5000, '2026-06-01', '2026-06-21'),   -- vencida
 (N'Black Friday TiendaTech',   'P', 20,   '2026-11-10', '2026-12-31'),   -- vigente en la evaluación
 (N'Liquidación de accesorios', 'M', 3000, '2026-11-10', '2026-12-31'),   -- vigente en la evaluación
 (N'Navidad anticipada',        'P', 12,   '2026-12-15', '2027-01-06');   -- futura

INSERT INTO dbo.PromocionProducto (PromocionId, ProductoId)
SELECT 1, ProductoId FROM dbo.Producto p JOIN dbo.Categoria c ON c.CategoriaId = p.CategoriaId WHERE c.Nombre IN (N'Laptops', N'Tablets')
UNION ALL
SELECT 2, ProductoId FROM dbo.Producto p JOIN dbo.Categoria c ON c.CategoriaId = p.CategoriaId WHERE c.Nombre IN (N'Teclados', N'Mouse', N'Monitores')
UNION ALL
SELECT 3, ProductoId FROM dbo.Producto p JOIN dbo.Categoria c ON c.CategoriaId = p.CategoriaId WHERE c.Nombre IN (N'Celulares', N'Audio')
UNION ALL   -- Audio queda en dos promociones a la vez: demuestra la regla de combinación (gana el mayor descuento)
SELECT 4, ProductoId FROM dbo.Producto p JOIN dbo.Categoria c ON c.CategoriaId = p.CategoriaId WHERE c.Nombre IN (N'Accesorios', N'Almacenamiento', N'Audio')
UNION ALL
SELECT 5, ProductoId FROM dbo.Producto p JOIN dbo.Categoria c ON c.CategoriaId = p.CategoriaId WHERE c.Nombre IN (N'Relojes inteligentes', N'Tablets');

/* ---------------- Pedidos: 2 por cada uno de 18 clientes = 36 ----------------
   Los clientes 19 y 20 no compran (sirven para el reporte R8).
   Todo se genera con aritmética modular: sin azar, siempre igual. */
CREATE TABLE #Ped (N INT NULL, ClienteId INT, K INT, Fecha DATETIME2(0), Lineas INT, EstadoId TINYINT NULL, MetodoPagoId INT NULL);
INSERT INTO #Ped (ClienteId, K, Fecha, Lineas)
SELECT c.ClienteId, k.K,
       DATEADD(HOUR, 8 + c.ClienteId % 10,
           CAST(DATEFROMPARTS(2026, x.Mes, CASE WHEN x.Mes = 11 THEN (c.ClienteId + k.K) % 5 + 1
                                                ELSE (c.ClienteId * 3 + k.K * 7) % 27 + 1 END) AS DATETIME2(0))),
       (c.ClienteId + k.K * 3) % 8 + 1
FROM dbo.Cliente c
CROSS JOIN (VALUES (1), (2)) k(K)
CROSS APPLY (SELECT (c.ClienteId * 2 + k.K * 5) % 11 + 1 AS Mes) x
WHERE c.ClienteId <= 18;

/* Número de pedido en orden cronológico. */
UPDATE p SET N = r.N
FROM #Ped p JOIN (SELECT ClienteId, K, ROW_NUMBER() OVER (ORDER BY Fecha, ClienteId, K) AS N FROM #Ped) r
  ON r.ClienteId = p.ClienteId AND r.K = p.K;

/* Estado final: los más recientes siguen en proceso; dos pedidos se cancelaron. */
UPDATE #Ped SET
    EstadoId = CASE WHEN N = 36 THEN 1 WHEN N IN (34,35) THEN 2 WHEN N IN (32,33) THEN 3
                    WHEN N IN (30,31) THEN 4 WHEN N IN (9,22) THEN 6 ELSE 5 END,
    MetodoPagoId = CASE WHEN N = 36 THEN 3 ELSE N % 4 + 1 END;

CREATE TABLE #Num (I INT PRIMARY KEY);
INSERT INTO #Num VALUES (1),(2),(3),(4),(5),(6),(7),(8);

/* Líneas: entre 1 y 8 productos distintos por pedido (11 es coprimo con 50). */
CREATE TABLE #Det (N INT, ProductoId INT, Cantidad INT, Precio DECIMAL(12,2), Descuento DECIMAL(12,2), Costo DECIMAL(12,2), PromocionId INT NULL);
INSERT INTO #Det (N, ProductoId, Cantidad, Precio, Descuento, Costo, PromocionId)
SELECT p.N, pr.ProductoId, (p.ClienteId + p.K + n.I) % 3 + 1, pr.Precio, ISNULL(pm.Descuento, 0), pr.Costo, pm.PromocionId
FROM #Ped p
JOIN #Num n ON n.I <= p.Lineas
JOIN dbo.Producto pr ON pr.ProductoId = (p.ClienteId * 7 + p.K * 13 + n.I * 11) % 50 + 1
OUTER APPLY (   -- misma regla que dbo.fn_MejorPromocion: la promoción vigente de mayor descuento
    SELECT TOP (1) m.PromocionId,
           CAST(CASE WHEN m.TipoDescuento = 'P' THEN ROUND(pr.Precio * m.Valor / 100.0, 2)
                     WHEN m.Valor > pr.Precio THEN pr.Precio ELSE m.Valor END AS DECIMAL(12,2)) AS Descuento
    FROM dbo.PromocionProducto pp JOIN dbo.Promocion m ON m.PromocionId = pp.PromocionId
    WHERE pp.ProductoId = pr.ProductoId AND m.Activo = 1
      AND CAST(p.Fecha AS DATE) BETWEEN m.FechaInicio AND m.FechaFin
    ORDER BY 2 DESC, m.PromocionId) pm;

SET IDENTITY_INSERT dbo.Pedido ON;
INSERT INTO dbo.Pedido (PedidoId, ClienteId, DireccionId, EstadoId, FechaPedido, Subtotal, DescuentoTotal, CostoEnvio)
SELECT p.N, p.ClienteId, p.ClienteId /* dirección predeterminada */, p.EstadoId, p.Fecha,
       t.Subtotal, t.Descuento, z.Tarifa
FROM #Ped p
JOIN (SELECT N, SUM(Cantidad * Precio) AS Subtotal, SUM(Cantidad * Descuento) AS Descuento FROM #Det GROUP BY N) t ON t.N = p.N
JOIN dbo.Direccion d ON d.DireccionId = p.ClienteId
JOIN dbo.ZonaEnvio z ON z.ZonaEnvioId = d.ZonaEnvioId
ORDER BY p.N;
SET IDENTITY_INSERT dbo.Pedido OFF;

INSERT INTO dbo.DetallePedido (PedidoId, ProductoId, Cantidad, PrecioUnitario, DescuentoUnitario, CostoUnitario, PromocionId)
SELECT N, ProductoId, Cantidad, Precio, Descuento, Costo, PromocionId FROM #Det ORDER BY N, ProductoId;

/* Historial de estados (lo que después hará el trigger). */
CREATE TABLE #Hist (PedidoId INT, Ant TINYINT NULL, Nuevo TINYINT, Fecha DATETIME2(3), UsuarioId INT, Comentario NVARCHAR(250));
INSERT INTO #Hist
SELECT N, NULL, 1, Fecha, ClienteId + 1, N'Pedido creado' FROM #Ped
UNION ALL SELECT N, 1, 2, DATEADD(MINUTE, 10, Fecha), 1, N'Pago aprobado' FROM #Ped WHERE EstadoId IN (2,3,4,5) OR N = 9
UNION ALL SELECT N, 2, 3, DATEADD(DAY, 1, Fecha), 1, N'Pedido en bodega' FROM #Ped WHERE EstadoId IN (3,4,5)
UNION ALL SELECT N, 3, 4, DATEADD(DAY, 2, Fecha), 1, N'Entregado al transportista' FROM #Ped WHERE EstadoId IN (4,5)
UNION ALL SELECT N, 4, 5, DATEADD(DAY, 4, Fecha), 1, N'Recibido por el cliente' FROM #Ped WHERE EstadoId = 5
UNION ALL SELECT N, 2, 6, DATEADD(DAY, 1, Fecha), ClienteId + 1, N'Cancelado por el cliente: ya no lo necesita' FROM #Ped WHERE N = 9
UNION ALL SELECT N, 1, 6, DATEADD(HOUR, 3, Fecha), ClienteId + 1, N'Cancelado por el cliente: pago no realizado' FROM #Ped WHERE N = 22;

INSERT INTO dbo.HistorialEstadoPedido (PedidoId, EstadoAnteriorId, EstadoNuevoId, Fecha, UsuarioId, Comentario)
SELECT PedidoId, Ant, Nuevo, Fecha, UsuarioId, Comentario FROM #Hist ORDER BY Fecha, PedidoId, Nuevo;

/* Pagos simulados: uno por pedido, por el total. */
INSERT INTO dbo.Pago (PedidoId, MetodoPagoId, Monto, Estado, Referencia, Fecha)
SELECT o.PedidoId, p.MetodoPagoId, o.Total,
       CASE WHEN p.N = 36 THEN 'PENDIENTE' WHEN p.N = 9 THEN 'REEMBOLSADO' WHEN p.N = 22 THEN 'ANULADO' ELSE 'APROBADO' END,
       'PAG-2026-' + RIGHT('00000' + CAST(p.N AS VARCHAR(5)), 5),
       DATEADD(MINUTE, 10, p.Fecha)
FROM #Ped p JOIN dbo.Pedido o ON o.PedidoId = p.N
ORDER BY p.N;

/* Envíos simulados: número de guía al despachar. */
INSERT INTO dbo.Envio (PedidoId, ZonaEnvioId, NumeroGuia, FechaDespacho, FechaEntrega)
SELECT p.N, d.ZonaEnvioId,
       CASE WHEN p.EstadoId IN (4,5) THEN 'TT-2026-' + RIGHT('00000' + CAST(p.N AS VARCHAR(5)), 5) END,
       CASE WHEN p.EstadoId IN (4,5) THEN DATEADD(DAY, 2, p.Fecha) END,
       CASE WHEN p.EstadoId = 5 THEN DATEADD(DAY, 4, p.Fecha) END
FROM #Ped p JOIN dbo.Direccion d ON d.DireccionId = p.ClienteId
ORDER BY p.N;

/* ---------------- Movimientos de inventario ---------------- */
CREATE TABLE #Mov (ProductoId INT, Tipo VARCHAR(10), Cantidad INT, Fecha DATETIME2(0), UsuarioId INT, Motivo NVARCHAR(200), PedidoId INT NULL);

-- a) Inventario inicial (55 entradas)
INSERT INTO #Mov
SELECT ProductoId, 'ENTRADA',
       CASE WHEN Precio >= 300000 THEN 14 WHEN Precio >= 100000 THEN 20 WHEN Precio >= 30000 THEN 30 ELSE 45 END,
       '2025-12-15T08:00:00', 1, N'Inventario inicial', NULL
FROM dbo.Producto;
-- b) Salidas por venta (una por línea de pedido)
INSERT INTO #Mov
SELECT d.ProductoId, 'SALIDA', -d.Cantidad, p.Fecha, p.ClienteId + 1, N'Venta, pedido #' + CAST(p.N AS NVARCHAR(10)), p.N
FROM #Det d JOIN #Ped p ON p.N = d.N;
-- c) Reintegro de los dos pedidos cancelados (una sola vez)
INSERT INTO #Mov
SELECT d.ProductoId, 'ENTRADA', d.Cantidad, h.Fecha, h.UsuarioId, N'Reintegro por cancelación, pedido #' + CAST(d.N AS NVARCHAR(10)), d.N
FROM #Det d JOIN #Hist h ON h.PedidoId = d.N AND h.Nuevo = 6;
-- d) Reabastecimientos y ajustes manuales
INSERT INTO #Mov VALUES
 ( 8, 'ENTRADA', 10, '2026-03-05T09:00:00', 1, N'Compra a proveedor, factura FP-1031', NULL),
 ( 9, 'ENTRADA', 10, '2026-03-05T09:10:00', 1, N'Compra a proveedor, factura FP-1031', NULL),
 (33, 'ENTRADA', 12, '2026-04-18T14:00:00', 1, N'Compra a proveedor, factura FP-1077', NULL),
 (28, 'ENTRADA', 15, '2026-05-22T10:30:00', 1, N'Compra a proveedor, factura FP-1102', NULL),
 (39, 'ENTRADA', 20, '2026-07-09T11:00:00', 1, N'Compra a proveedor, factura FP-1160', NULL),
 ( 1, 'ENTRADA',  6, '2026-08-14T09:00:00', 1, N'Compra a proveedor, factura FP-1203', NULL),
 (41, 'AJUSTE',  -3, '2026-02-10T16:00:00', 1, N'Conteo físico: faltante', NULL),
 (30, 'AJUSTE',  -2, '2026-04-02T16:00:00', 1, N'Producto dañado en bodega', NULL),
 (47, 'AJUSTE',   2, '2026-06-30T17:00:00', 1, N'Conteo físico: sobrante', NULL),
 (20, 'AJUSTE',  -1, '2026-08-01T16:30:00', 1, N'Pantalla quebrada en exhibición', NULL),
 ( 5, 'AJUSTE',  -6, '2026-09-12T16:00:00', 1, N'Devolución a proveedor por defecto de fábrica', NULL),
 (18, 'AJUSTE',  -6, '2026-10-03T16:00:00', 1, N'Lote retirado por garantía del fabricante', NULL),
 (14, 'AJUSTE', -10, '2026-10-20T16:00:00', 1, N'Unidades trasladadas a tienda física', NULL),
 (51, 'AJUSTE', -45, '2026-10-25T16:00:00', 1, N'Unidades trasladadas a tienda física', NULL);

INSERT INTO dbo.MovimientoInventario (ProductoId, Tipo, Cantidad, ExistenciaResultante, Fecha, UsuarioId, Motivo, PedidoId)
SELECT ProductoId, Tipo, Cantidad, 0, Fecha, UsuarioId, Motivo, PedidoId
FROM #Mov ORDER BY Fecha, PedidoId, ProductoId;

/* Existencia resultante = saldo acumulado. Si algún saldo fuera negativo,
   el CHECK CK_Movimiento_Resultante detiene el script. */
UPDATE m SET ExistenciaResultante = s.Saldo
FROM dbo.MovimientoInventario m
JOIN (SELECT MovimientoId,
             SUM(Cantidad) OVER (PARTITION BY ProductoId ORDER BY Fecha, MovimientoId ROWS UNBOUNDED PRECEDING) AS Saldo
      FROM dbo.MovimientoInventario) s ON s.MovimientoId = m.MovimientoId;

/* Existencia actual = suma de movimientos. */
UPDATE i SET Existencia = s.Saldo, FechaActualizacion = s.Ultima
FROM dbo.Inventario i
JOIN (SELECT ProductoId, SUM(Cantidad) AS Saldo, MAX(Fecha) AS Ultima FROM dbo.MovimientoInventario GROUP BY ProductoId) s
  ON s.ProductoId = i.ProductoId;

/* ---------------- Reseñas (20) ----------------
   Solo de productos que el cliente recibió (pedido Entregado). */
INSERT INTO dbo.Resena (ClienteId, ProductoId, Calificacion, Comentario, Fecha)
SELECT TOP (20) x.ClienteId, x.ProductoId, x.Calificacion,
       CASE x.Calificacion WHEN 5 THEN N'Excelente producto, llegó antes de lo esperado.'
                           WHEN 4 THEN N'Muy buena calidad por el precio. Lo recomiendo.'
                           WHEN 3 THEN N'Cumple con lo que promete, sin más.'
                           ELSE N'Esperaba mejor calidad, el empaque llegó golpeado.' END,
       DATEADD(DAY, 7, x.Fecha)
FROM (SELECT o.ClienteId, d.ProductoId, MIN(o.FechaPedido) AS Fecha,
             CASE (o.ClienteId * 3 + d.ProductoId) % 6 WHEN 0 THEN 5 WHEN 1 THEN 4 WHEN 2 THEN 5 WHEN 3 THEN 3 WHEN 4 THEN 4 ELSE 2 END AS Calificacion,
             ROW_NUMBER() OVER (PARTITION BY o.ClienteId ORDER BY d.ProductoId) AS Rn
      FROM dbo.Pedido o JOIN dbo.DetallePedido d ON d.PedidoId = o.PedidoId
      WHERE o.EstadoId = 5
      GROUP BY o.ClienteId, d.ProductoId) x
ORDER BY x.Rn, x.ClienteId;

/* ---------------- Carritos persistentes de ejemplo ---------------- */
INSERT INTO dbo.Carrito (ClienteId, FechaCreacion, FechaActualizacion) VALUES
 (1, '2026-11-08T19:00:00', '2026-11-08T19:05:00'), (19, '2026-11-09T12:00:00', '2026-11-09T12:02:00');
INSERT INTO dbo.DetalleCarrito (CarritoId, ProductoId, Cantidad, FechaAgregado) VALUES
 (1, 34, 1, '2026-11-08T19:00:00'), (1, 51, 2, '2026-11-08T19:05:00'), (2, 11, 1, '2026-11-09T12:02:00');

/* ---------------- Verificación de coherencia ---------------- */
IF EXISTS (SELECT 1 FROM dbo.Inventario i
           WHERE i.Existencia <> (SELECT ISNULL(SUM(m.Cantidad), 0) FROM dbo.MovimientoInventario m WHERE m.ProductoId = i.ProductoId))
    THROW 50000, N'Datos incoherentes: la existencia no concilia con los movimientos.', 1;
IF EXISTS (SELECT 1 FROM dbo.Pedido o
           WHERE o.Subtotal - o.DescuentoTotal <> (SELECT SUM(d.TotalLinea) FROM dbo.DetallePedido d WHERE d.PedidoId = o.PedidoId))
    THROW 50000, N'Datos incoherentes: el encabezado del pedido no concilia con su detalle.', 1;
IF EXISTS (SELECT 1 FROM dbo.Pedido o JOIN dbo.Pago g ON g.PedidoId = o.PedidoId WHERE g.Monto <> o.Total)
    THROW 50000, N'Datos incoherentes: el pago no coincide con el total del pedido.', 1;

COMMIT TRANSACTION;
GO
DROP TABLE #Ped, #Det, #Num, #Hist, #Mov;
GO
SELECT 'Marcas' AS Entidad, COUNT(*) AS Registros FROM dbo.Marca
UNION ALL SELECT 'Categorías', COUNT(*) FROM dbo.Categoria
UNION ALL SELECT 'Productos', COUNT(*) FROM dbo.Producto
UNION ALL SELECT 'Clientes', COUNT(*) FROM dbo.Cliente
UNION ALL SELECT 'Pedidos', COUNT(*) FROM dbo.Pedido
UNION ALL SELECT 'Líneas de pedido', COUNT(*) FROM dbo.DetallePedido
UNION ALL SELECT 'Promociones', COUNT(*) FROM dbo.Promocion
UNION ALL SELECT 'Reseñas', COUNT(*) FROM dbo.Resena
UNION ALL SELECT 'Movimientos de inventario', COUNT(*) FROM dbo.MovimientoInventario
UNION ALL SELECT 'Productos bajo mínimo', COUNT(*) FROM dbo.Inventario WHERE Existencia < StockMinimo;
PRINT '02_datos.sql: datos de prueba cargados y conciliados.';
GO
