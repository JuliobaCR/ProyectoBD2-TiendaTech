# Evidencias de los reportes (Compañera 2)

Rama: `evidencias-reportes`. Los pasos para subir están en `docs/TAREAS_EQUIPO.md`.

Ingresar a la aplicación como administrador (usuario en el `README.md`) e ir a
**Administración → Reportes**.

## Archivos que hay que agregar a esta carpeta

| Archivo | Cómo se obtiene |
|---|---|
| `R01.png` … `R10.png` | Una captura de cada reporte en la aplicación, del R1 al R10 (diez archivos). |
| `R04_ssms.png` | En SSMS, sobre la base `TiendaTechDB`, ejecutar `EXEC dbo.usp_Reporte_R4;` con los mismos filtros que en la aplicación y capturar el resultado. Sirve para mostrar que la aplicación y SQL Server dan lo mismo. |
| `R02_ssms.png` | Lo mismo con `EXEC dbo.usp_Reporte_R2;` (es el reporte con PIVOT). |
| `R04.csv` y `R06.csv` | En la aplicación, abrir esos reportes y usar el botón de exportar a CSV. Guardar aquí los dos archivos descargados. |

Si un procedimiento pide parámetros, se ven en `sql/06_reportes.sql`.

## Observaciones

Integrante: _(su nombre)_

Fecha en que se ejecutó: _(fecha)_

Una línea por reporte explicando qué responde y qué técnica de SQL usa (HAVING,
subconsulta, PIVOT, RANK, LAG…). La técnica está en el comentario de cada
procedimiento en `sql/06_reportes.sql`:

- R1:
- R2:
- R3:
- R4:
- R5:
- R6:
- R7:
- R8:
- R9:
- R10:
