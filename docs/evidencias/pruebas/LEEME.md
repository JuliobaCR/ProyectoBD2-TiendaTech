# Evidencias de pruebas, concurrencia e índices (Compañera 1)

Rama: `evidencias-pruebas`. Los pasos para subir están en `docs/TAREAS_EQUIPO.md`.

## Archivos que hay que agregar a esta carpeta

| Archivo | Cómo se obtiene |
|---|---|
| `01_pruebas_resultado.png` | Abrir `sql/07_pruebas.sql` en SSMS, presionar F5 y capturar la tabla final: deben salir 20 pruebas en PASA. |
| `02_pruebas_mensajes.png` | En esa misma ejecución, capturar la pestaña **Messages**. |
| `03_sobreventa.png` | Captura de la fila de la prueba de sobreventa (el checkout se rechaza y el inventario no cambia). |
| `04_concurrencia.png` | En una consola, dentro de la carpeta del proyecto, ejecutar `.venv\Scripts\python pruebas\prueba_concurrencia.py` y capturar la salida: de dos compras simultáneas de la última unidad, solo una se confirma. |
| `05_indices_lecturas.png` | Abrir `sql/09_evidencia_indices.sql` en SSMS, activar **Include Actual Execution Plan** (Ctrl+M), presionar F5 y capturar **Messages** con las lecturas lógicas antes y después del índice. |
| `06_indices_plan.png` | En esa misma ejecución, capturar un plan donde aparezca **Index Seek**. |

Después de `07_pruebas.sql` conviene volver a ejecutar `instalar_bd.bat` para dejar la
base limpia. `09_evidencia_indices.sql` no deja cambios (termina con ROLLBACK).

## Observaciones

Integrante: _(su nombre)_

Fecha en que se ejecutó: _(fecha)_

Una línea por captura explicando qué demuestra:

- `01_pruebas_resultado.png`:
- `02_pruebas_mensajes.png`:
- `03_sobreventa.png`:
- `04_concurrencia.png`:
- `05_indices_lecturas.png`:
- `06_indices_plan.png`:
