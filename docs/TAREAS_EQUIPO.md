# Tareas del equipo antes de la entrega

La base de datos, la aplicación, las pruebas automáticas y el documento de diseño ya
están en el repositorio. Falta la **evidencia de ejecución** (capturas y archivos
exportados) que pide el enunciado, y que cada integrante pueda explicar su parte en
la defensa del **4 de diciembre**.

Cada integrante tiene una carpeta propia dentro de `docs/evidencias/`. Dentro de cada
carpeta hay un `LEEME.md` con la lista exacta de archivos que hay que agregar.

## 1. Reparto

| Integrante | Tarea | Carpeta | Tiempo | Rama |
|---|---|---|---|---|
| Julio | Portada del documento con los nombres, repositorio, revisar y aprobar lo que suban las demás | `docs/` | 30 min | `main` |
| Compañera 1 | Evidencia de las pruebas SQL, de la concurrencia y de los índices | `docs/evidencias/pruebas/` | 45 min | `evidencias-pruebas` |
| Compañera 2 | Evidencia de los 10 reportes y de las exportaciones a CSV | `docs/evidencias/reportes/` | 45 min | `evidencias-reportes` |
| Compañera 3 | Evidencia de la aplicación (flujo de compra y administración) y diagrama ER desde SSMS | `docs/evidencias/aplicacion/` | 45 min | `evidencias-aplicacion` |

Pónganse de acuerdo en quién es la Compañera 1, 2 y 3 y anótenlo aquí.

## 2. Pasos para cada compañera

### 2.1 Una sola vez: preparar la computadora

1. Instalar [SQL Server Express](https://www.microsoft.com/es-es/sql-server/sql-server-downloads),
   [SSMS](https://learn.microsoft.com/es-es/ssms/install/install),
   [Python 3](https://www.python.org/downloads/) y [Git](https://git-scm.com/downloads).
2. Aceptar la invitación al repositorio que llega por correo.
3. Clonar el repositorio y entrar a la carpeta:

```bat
git clone https://github.com/JuliobaCR/ProyectoBD2-TiendaTech.git
cd ProyectoBD2-TiendaTech
```

4. Crear la base de datos con doble clic en `instalar_bd.bat`.
5. Abrir la aplicación con doble clic en `iniciar_app.bat` (la primera vez tarda un
   poco porque instala las dependencias). Usuarios de demostración en el `README.md`.

Si algo de esto falla, el `README.md` tiene la instalación detallada y los problemas comunes.

### 2.2 Hacer la tarea y subirla

```bat
git config user.name "Su Nombre Apellido"
git config user.email "el-correo-de-su-cuenta-de-github"
git checkout -b evidencias-pruebas
```

(cada una usa el nombre de rama que le toca en la tabla de arriba)

Luego:

1. Hacer las capturas que indica el `LEEME.md` de su carpeta y guardarlas ahí con los
   nombres que se piden.
2. Completar la sección "Observaciones" de ese mismo `LEEME.md` con su nombre y una
   línea por captura explicando qué demuestra. Esto es lo que van a decir en la defensa.
3. Subir el trabajo:

```bat
git add docs/evidencias
git commit -m "Evidencias de las pruebas SQL"
git push -u origin evidencias-pruebas
```

4. En GitHub aparece un botón **Compare & pull request**: presionarlo y crear el pull
   request. Julio lo revisa y lo aprueba.

Es mejor hacer varios commits pequeños (por ejemplo, uno por cada grupo de capturas)
que uno solo al final: el profesor revisa el historial.

## 3. Qué debe poder explicar cada integrante

El profesor puede pedir a cada uno que explique partes del modelo, un procedimiento
almacenado y una consulta analítica, y las preguntas son individuales.

| Integrante | Parte del modelo | Procedimiento | Consulta analítica |
|---|---|---|---|
| Julio | Pedido, DetallePedido, estados y transiciones | `usp_Pedido_Confirmar` (checkout atómico) | R9 (LAG) y R4 |
| Compañera 1 | Producto, Inventario, MovimientoInventario | `usp_Pedido_Cancelar` y `usp_Inventario_RegistrarMovimiento` | R6 y R7 (rentabilidad) |
| Compañera 2 | Promocion, PromocionProducto, Resena | `usp_Carrito_Agregar` y `fn_MejorPromocion` | R2 (PIVOT) y R5 (RANK) |
| Compañera 3 | Usuario, Cliente, Direccion, auditoría | Triggers de `05_triggers.sql` y `usp_Cliente_Registrar` | R1 (HAVING) y R8 (NOT EXISTS) |

Para estudiar: leer en `docs/Documento_Diseno.pdf` la sección de su parte del modelo,
abrir su procedimiento en `sql/03_procedimientos.sql` (o `sql/05_triggers.sql`) y
ejecutar sus reportes en SSMS, por ejemplo `EXEC dbo.usp_Reporte_R6;`.

Preguntas probables y dónde está la respuesta:

- **¿Cómo evitan la sobreventa?** `UPDATE … WHERE Existencia >= Cantidad` dentro de la
  transacción, más el `CHECK (Existencia >= 0)`. Documento, sección 8.
- **¿Qué pasa si falla a mitad del checkout?** El `CATCH` hace `ROLLBACK` y `THROW`. Pruebas 2 y 3.
- **¿Por qué el trigger funciona con varias filas?** Usa `inserted` y `deleted` con JOIN,
  sin variables. Prueba 8.
- **¿Cómo sabe el trigger qué usuario hizo el cambio?** `SESSION_CONTEXT`, que fijan los procedimientos.
- **¿Por qué guardan el total en el pedido si se puede calcular?** Documento, sección 5,
  "Desnormalizaciones justificadas".
- **¿Dónde está la 3FN?** Documento, sección 5.
- **¿La aplicación arma SQL?** No: `app/db.py` solo ejecuta `EXEC dbo.usp_… @p = ?`.
- **¿Y el SQL dinámico de R2?** Columnas tomadas de la tabla `Categoria` con `QUOTENAME`;
  ninguna entrada del usuario se concatena.

## 4. Tareas de Julio

1. Invitar a las compañeras y al profesor: en GitHub, *Settings → Collaborators → Add people*.
2. Completar la portada: editar las constantes de la sección `PORTADA` en
   `herramientas/generar_documento.py` (institución, profesor, grupo, integrantes) y
   ejecutar `.venv\Scripts\python herramientas\generar_documento.py`. Se regenera
   `docs/Documento_Diseno.pdf`.
3. Revisar y aprobar los tres pull requests.

## 5. Lista de verificación final

- [ ] `instalar_bd.bat` corre sin errores en una máquina limpia.
- [ ] `07_pruebas.sql` termina con 20 de 20 en PASA.
- [ ] La aplicación abre e ingresan el administrador y un cliente.
- [ ] La portada del PDF tiene los nombres reales.
- [ ] Las tres carpetas de `docs/evidencias/` tienen sus capturas y observaciones.
- [ ] `app/.env` no está en el repositorio.
- [ ] Los cuatro integrantes tienen commits.
- [ ] Las promociones siguen vigentes en la fecha de la defensa (vencen el 31 de diciembre de 2026).
