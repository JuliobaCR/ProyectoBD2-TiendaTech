# TiendaTech — Proyecto Programado II de Bases de Datos

Sistema de comercio electrónico para una tienda de tecnología (laptops, celulares,
periféricos y accesorios), construido sobre **Microsoft SQL Server**. La lógica de
negocio vive en la base de datos (procedimientos almacenados, vistas y triggers en
Transact-SQL) y una aplicación web en Python/Flask la consume.

| Elemento | Cantidad |
|---|---|
| Tablas | 25 |
| Procedimientos almacenados | 80 (más 1 función) |
| Vistas | 5 |
| Triggers | 3 |
| Índices no agrupados | 11 (8 de rendimiento y 3 únicos filtrados) |
| Reportes analíticos | R1 a R10 |
| Pruebas automáticas | 20 en SQL y 1 de concurrencia |

## 1. Prerrequisitos

- **Microsoft SQL Server 2019 o superior** (desarrollado y probado en SQL Server 2025
  Express, instancia `localhost\SQLEXPRESS`). Se usan `STRING_AGG`, `CREATE OR ALTER`
  y `SESSION_CONTEXT`, por lo que no funciona en versiones anteriores a 2017.
- **sqlcmd** (se instala con SQL Server o con SSMS) y **ODBC Driver 17 o 18 for SQL Server**.
- **Python 3.10 o superior**.
- Un usuario de Windows con permiso para crear bases de datos en la instancia.

## 2. Instalación de la base de datos

Desde la carpeta del proyecto:

```bat
instalar_bd.bat
```

Para otra instancia: `instalar_bd.bat SERVIDOR\INSTANCIA`.

El instalador ejecuta los scripts en orden y se detiene si alguno falla. Si
`TiendaTechDB` ya existe, **la elimina y la vuelve a crear** (instalación reproducible).

También se pueden ejecutar a mano, en este orden, desde SSMS o con sqlcmd:

| Orden | Script | Contenido |
|---|---|---|
| 1 | `sql/01_esquema.sql` | Base de datos, tablas, restricciones e índices |
| 2 | `sql/02_datos.sql` | Datos de prueba reproducibles y conciliados |
| 3 | `sql/03_procedimientos.sql` | Función `fn_MejorPromocion` y procedimientos |
| 4 | `sql/04_vistas.sql` | Vistas |
| 5 | `sql/05_triggers.sql` | Triggers de auditoría e inmutabilidad |
| 6 | `sql/06_reportes.sql` | Reportes R1–R10 |
| 7 | `sql/07_pruebas.sql` | Casos de prueba (opcional; no es parte de la instalación) |
| 8 | `sql/08_seguridad.sql` | Rol y usuario de mínimo privilegio para la aplicación |
| — | `sql/09_evidencia_indices.sql` | Evidencia del impacto de los índices (opcional) |

```bat
sqlcmd -S localhost\SQLEXPRESS -E -C -f 65001 -i sql\01_esquema.sql
```

`-f 65001` hace que sqlcmd lea los scripts como UTF-8 (tildes y ñ). En SSMS basta con
abrir el archivo y presionar F5.

## 3. Instalación y ejecución de la aplicación

La forma rápida es hacer doble clic en `iniciar_app.bat`: crea el entorno de Python si
no existe, arranca el servidor y abre el navegador. Los pasos manuales equivalentes son:

```bat
python -m venv .venv
.venv\Scripts\python -m pip install -r app\requirements.txt
.venv\Scripts\python herramientas\generar_imagenes.py
.venv\Scripts\python app\app.py
```

Luego abrir <http://localhost:5000>.

- La configuración por defecto usa `localhost\SQLEXPRESS` con autenticación de Windows.
  Para cambiarla, copiar `app/config.example.env` como `app/.env` y editarlo. El `.env`
  no se sube a Git y el ejemplo no contiene contraseñas ni secretos.
- `generar_imagenes.py` crea las imágenes de los productos (SVG propios, sin internet).
  Las imágenes ya vienen en el repositorio; solo hay que volver a correrlo si se borran.
- Si `pyodbc` no se puede cargar (en algunos equipos Windows bloquea su DLL), la
  aplicación usa sola `pypyodbc`, que es Python puro. No hay que configurar nada.

## 4. Usuarios de demostración

Son cuentas ficticias que carga `02_datos.sql`. En la base solo está el hash (scrypt).

| Rol | Correo | Contraseña |
|---|---|---|
| Administrador | `admin@tiendatech.test` | `Admin123*` |
| Cliente | `cliente01@correo.test` … `cliente20@correo.test` | `Cliente123*` |

Clientes útiles para la demostración:

- `cliente01`: tiene pedidos, reseñas y un carrito guardado con un producto agotado
  (sirve para mostrar el rechazo del checkout por falta de existencias).
- `cliente19` y `cliente20`: nunca han comprado (aparecen en el reporte R8).

## 5. Cómo está organizado

```
ProyectoBD2/
├── instalar_bd.bat            instalador de la base de datos
├── sql/                       scripts numerados (entregable principal)
├── app/                       aplicación web Flask
│   ├── app.py                 arranque, filtros, protección CSRF
│   ├── db.py                  ÚNICO punto de acceso a SQL Server: solo EXEC de procedimientos
│   ├── tienda.py              pantallas del cliente
│   ├── admin.py               pantallas del administrador
│   ├── reportes.py            panel de reportes R1–R10 y exportación CSV
│   ├── templates/, static/    HTML, CSS e imágenes
│   └── config.example.env     configuración de ejemplo, sin secretos
├── pruebas/prueba_concurrencia.py   prueba 10 (dos compras simultáneas)
├── herramientas/              generadores de imágenes y del documento
└── docs/                      documento de diseño (HTML y PDF)
```

### Pantallas

| Rol | Pantallas |
|---|---|
| Visitante | Catálogo con búsqueda y filtros, detalle de producto, ingreso, registro |
| Cliente | Carrito, checkout, historial y detalle de pedidos, comprobante imprimible, perfil, direcciones, reseñas |
| Administrador | Panel con alertas, productos, marcas, categorías, clientes, promociones, pedidos, inventario, conciliación, auditoría, reportes |

### Reglas que la aplicación NO decide

La interfaz valida formato (campos obligatorios, números), pero las reglas críticas
están en SQL Server y se pueden comprobar desde SSMS sin la aplicación:

- **Checkout atómico** (`usp_Pedido_Confirmar`): una transacción con `TRY…CATCH`; si
  falta existencia de un solo producto se hace `ROLLBACK` de todo.
- **Sin sobreventa**: el descuento de inventario es un `UPDATE … WHERE Existencia >= Cantidad`,
  más la restricción `CHECK (Existencia >= 0)`.
- **Estados**: las transiciones válidas están en la tabla `TransicionEstado`.
- **Cancelación**: solo antes del envío; reintegra existencias una única vez.
- **Precio histórico**: el detalle del pedido guarda precio, descuento y costo del momento.
- **Promociones**: no se acumulan; gana la de mayor descuento (`fn_MejorPromocion`).
- **Reseñas**: una por cliente y producto, y solo de productos recibidos.
- **Auditoría**: triggers multi-fila para cambios de precio y de estado.
- **Mínimo privilegio**: la aplicación opera como `app_tiendatech`, que solo puede
  ejecutar procedimientos; un `SELECT` directo a una tabla le da "permission denied".

## 6. Ruta de reproducción de pruebas

### 6.1 Pruebas automáticas en SQL (pruebas 1 a 9 y 11 a 13)

```bat
sqlcmd -S localhost\SQLEXPRESS -E -C -f 65001 -W -i sql\07_pruebas.sql
```

Al final imprime una tabla con **datos esperados, resultado obtenido y PASA/FALLA**.
Resultado esperado: `20 pruebas, 20 pasan, 0 fallan`. Las pruebas que tocan ventas o
precios corren dentro de una transacción que se revierte, por lo que los reportes no
cambian; la prueba 4 deja un pedido cancelado (no cuenta como venta).

| Prueba | Qué demuestra |
|---|---|
| 1 | Compra exitosa y descuento correcto del inventario |
| 2 | Compra fallida por falta de existencias y `ROLLBACK` |
| 3 | Pedido con dos productos, uno sin stock: ningún inventario afectado |
| 4a, 4b | Cancelación con reintegro; segundo intento sin reintegro duplicado |
| 5a, 5b | Transiciones de estado inválidas |
| 6 | Cambio de precio sin alterar el precio histórico de los pedidos |
| 7a–7d | Duplicados y valores inválidos rechazados por restricciones |
| 8a, 8b | Triggers de auditoría con una actualización de varias filas |
| 9 | Reporte R4 contra una consulta SQL directa |
| 11a, 11b | Inventario: sin existencia negativa; movimientos inmutables |
| 12a, 12b | Reseña duplicada y reseña de un producto no comprado |
| 13 | Conciliación: existencia = suma de movimientos |

### 6.2 Prueba 10: dos compras simultáneas sin sobreventa

```bat
.venv\Scripts\python pruebas\prueba_concurrencia.py
```

Deja una sola unidad de un producto y lanza dos compradores al mismo tiempo. Uno
confirma y el otro recibe "Existencia insuficiente"; la existencia termina en 0. La
prueba restaura los datos al final. La versión manual con dos ventanas de SSMS está
explicada al final de `sql/07_pruebas.sql`.

### 6.3 Evidencia de índices

Ejecutar `sql/09_evidencia_indices.sql` en SSMS con el plan de ejecución real activado
(Ctrl+M). Carga un volumen temporal, compara lecturas lógicas con y sin cada índice y
revierte todo. Resultado medido:

| Consulta | Sin el índice | Con el índice |
|---|---|---|
| Historial de pedidos de un cliente (`IX_Pedido_Cliente_Fecha`) | 324 lecturas | 2 lecturas |
| Pedidos por rango de fechas (`IX_Pedido_Fecha`) | 324 | 6 |
| Ventas de un producto (`IX_DetallePedido_Producto`) | 917 | 19 |
| Catálogo por categoría (`IX_Producto_Categoria`) | 5 | 2 |

### 6.4 Las mismas pruebas desde la interfaz

1. **Compra exitosa**: ingresar como `cliente02`, agregar productos, checkout con tarjeta.
   Ver el pedido Confirmado y, como administrador, el movimiento de SALIDA en Inventario.
2. **Falta de existencias**: ingresar como `cliente01` e ir directo al checkout; su
   carrito trae un producto agotado y el pedido se rechaza completo.
3. **Cancelación**: en el detalle de un pedido Pendiente o Confirmado, cancelar; volver
   a intentarlo desde Administración → Pedidos muestra el rechazo.
4. **Transición inválida**: Administración → Pedidos → cualquier pedido Entregado →
   elegir "Pendiente" en "Cambiar estado".
5. **Precio histórico y trigger multi-fila**: Administración → Auditoría → cambio masivo
   de precios; luego revisar un pedido anterior: conserva el precio original.
6. **Duplicado**: Administración → Marcas → crear "Apple".
7. **Reporte contra SQL**: Administración → Reportes → R4, y comparar con
   `EXEC dbo.usp_Reporte_R4_EvolucionMensual @Anio = 2026;` en SSMS.

### 6.5 Exportaciones

- **CSV / Excel**: botón "Exportar a CSV / Excel" en cada uno de los diez reportes.
- **PDF / impresión de un pedido**: botón "Imprimir / guardar PDF" en el detalle del pedido.

## 7. Notas sobre los datos de prueba

- Todo es ficticio. Las fechas son fijas en 2026, así que cada instalación produce
  exactamente los mismos datos y los mismos totales en los reportes.
- Las promociones "vigentes" van del 10 de noviembre al 31 de diciembre de 2026. Si el
  proyecto se revisa fuera de ese rango, ajustar las fechas en Administración → Promociones.
- Totales de referencia recién instalado: 36 pedidos (34 ventas y 2 cancelados),
  ventas por ₡59 146 750 y 4 productos bajo el mínimo.

## 8. Control de versiones y participación

El repositorio Git registra el aporte de cada integrante. La distribución del trabajo
y las tareas pendientes del equipo están en `docs/TAREAS_EQUIPO.md`.
