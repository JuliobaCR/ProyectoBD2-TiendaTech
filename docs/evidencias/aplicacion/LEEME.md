# Evidencias de la aplicación y diagrama ER (Compañera 3)

Rama: `evidencias-aplicacion`. Los pasos para subir están en `docs/TAREAS_EQUIPO.md`.

Los usuarios de demostración (un cliente y el administrador) están en el `README.md`.

## Archivos que hay que agregar a esta carpeta

Como cliente:

| Archivo | Qué capturar |
|---|---|
| `01_catalogo.png` | La portada con el catálogo y las promociones. |
| `02_detalle_producto.png` | El detalle de un producto con su precio, existencia y reseñas. |
| `03_carrito.png` | El carrito con al menos dos productos. |
| `04_checkout.png` | La pantalla de confirmación de la compra. |
| `05_pedido.png` | El pedido ya confirmado, con su historial de estados. |
| `06_comprobante.pdf` | En el pedido, abrir la versión para imprimir y guardarla como PDF. |
| `07_sin_existencias.png` | Intentar comprar más unidades de las que hay y capturar el mensaje de error. |

Como administrador:

| Archivo | Qué capturar |
|---|---|
| `08_panel.png` | El panel de administración con los indicadores. |
| `09_inventario.png` | La pantalla de inventario con los movimientos. |
| `10_cambio_estado.png` | Un pedido después de cambiarle el estado (por ejemplo, de Pagado a Enviado). |
| `11_auditoria.png` | La pantalla de auditoría después de cambiar el precio de un producto: debe verse el precio anterior y el nuevo. |

Diagrama:

| Archivo | Cómo se obtiene |
|---|---|
| `12_diagrama_er_ssms.png` | En SSMS, dentro de `TiendaTechDB`, clic derecho en **Database Diagrams → New Database Diagram**, agregar todas las tablas, acomodarlas y capturar (o clic derecho en el diagrama → *Copy Diagram to Clipboard* y pegar en Paint). |

## Observaciones

Integrante: _(su nombre)_

Fecha en que se ejecutó: _(fecha)_

Una línea por captura explicando qué demuestra y qué procedimiento almacenado se
ejecuta detrás (se puede ver en `app/tienda.py` y `app/admin.py`, buscando `usp_`):

- `01_catalogo.png`:
- `02_detalle_producto.png`:
- `03_carrito.png`:
- `04_checkout.png`:
- `05_pedido.png`:
- `06_comprobante.pdf`:
- `07_sin_existencias.png`:
- `08_panel.png`:
- `09_inventario.png`:
- `10_cambio_estado.png`:
- `11_auditoria.png`:
- `12_diagrama_er_ssms.png`:
