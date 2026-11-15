"""Genera el documento de diseño: docs/Documento_Diseno.html y docs/Documento_Diseno.pdf.

El diccionario de datos, las restricciones, los índices y la lista de procedimientos
se leen de la base TiendaTechDB ya instalada (con sqlcmd), así el documento nunca
queda desactualizado respecto de los scripts.

Uso (desde la raíz del proyecto):
    .venv\\Scripts\\python herramientas\\generar_documento.py
    .venv\\Scripts\\python herramientas\\generar_documento.py SERVIDOR\\INSTANCIA

ANTES DE ENTREGAR: complete los datos de la portada aquí abajo y vuelva a ejecutar.
El diagrama ER se dibuja con Mermaid (se descarga de internet al generar el PDF).
"""
import html
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# ----------------------------------------------------------------- PORTADA (editar)
INSTITUCION = "Nombre de la institución"
CURSO = "Bases de Datos"
PROFESOR = "Nombre del profesor"
GRUPO = "Grupo __"
INTEGRANTES = [
    "Nombre Apellido Apellido — carné",
    "Nombre Apellido Apellido — carné",
    "Nombre Apellido Apellido — carné",
    "Nombre Apellido Apellido — carné",
]
FECHA_ENTREGA = "4 de diciembre de 2026"
# -----------------------------------------------------------------

RAIZ = Path(__file__).resolve().parent.parent
SERVIDOR = sys.argv[1] if len(sys.argv) > 1 else r"localhost\SQLEXPRESS"
BASE = "TiendaTechDB"
e = html.escape


def consultar(sql: str) -> list[list[str]]:
    """Ejecuta una consulta con sqlcmd y devuelve las filas como listas de texto."""
    with tempfile.TemporaryDirectory() as tmp:
        salida = Path(tmp) / "salida.txt"
        subprocess.run(["sqlcmd", "-S", SERVIDOR, "-E", "-C", "-d", BASE, "-l", "60", "-W", "-h", "-1", "-s", "\t",
                        "-u", "-o", str(salida), "-Q", "SET NOCOUNT ON; " + sql], check=True)
        texto = salida.read_text(encoding="utf-16")
    return [linea.split("\t") for linea in texto.splitlines() if linea.strip()]


# ================================================================= metadatos
SQL_COLUMNAS = """
SELECT t.name, c.name,
       TYPE_NAME(c.user_type_id) + CASE
           WHEN TYPE_NAME(c.user_type_id) IN ('varchar','char') THEN '(' + CAST(c.max_length AS VARCHAR(5)) + ')'
           WHEN TYPE_NAME(c.user_type_id) IN ('nvarchar','nchar') THEN '(' + CAST(c.max_length / 2 AS VARCHAR(5)) + ')'
           WHEN TYPE_NAME(c.user_type_id) IN ('decimal','numeric') THEN '(' + CAST(c.precision AS VARCHAR(3)) + ',' + CAST(c.scale AS VARCHAR(3)) + ')'
           WHEN TYPE_NAME(c.user_type_id) = 'datetime2' THEN '(' + CAST(c.scale AS VARCHAR(1)) + ')'
           ELSE '' END,
       CASE WHEN c.is_nullable = 1 THEN 'Sí' ELSE 'No' END,
       ISNULL(dc.definition, '-'),
       CASE WHEN pk.column_id IS NOT NULL THEN 'PK' ELSE '-' END,
       ISNULL(OBJECT_NAME(fk.referenced_object_id) + '.' + COL_NAME(fk.referenced_object_id, fk.referenced_column_id), '-'),
       CASE WHEN c.is_identity = 1 THEN 'IDENTITY' WHEN c.is_computed = 1 THEN 'CALCULADA' ELSE '-' END
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
LEFT JOIN sys.default_constraints dc ON dc.object_id = c.default_object_id
LEFT JOIN (SELECT ic.object_id, ic.column_id FROM sys.indexes i
           JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
           WHERE i.is_primary_key = 1) pk ON pk.object_id = c.object_id AND pk.column_id = c.column_id
LEFT JOIN sys.foreign_key_columns fk ON fk.parent_object_id = c.object_id AND fk.parent_column_id = c.column_id
ORDER BY t.name, c.column_id;
"""
SQL_CHECKS = """
SELECT OBJECT_NAME(parent_object_id), name, 'CHECK', definition FROM sys.check_constraints
UNION ALL
SELECT OBJECT_NAME(k.parent_object_id), k.name, 'UNIQUE',
       (SELECT STRING_AGG(COL_NAME(ic.object_id, ic.column_id), ', ') WITHIN GROUP (ORDER BY ic.key_ordinal)
        FROM sys.index_columns ic WHERE ic.object_id = k.parent_object_id AND ic.index_id = k.unique_index_id)
FROM sys.key_constraints k WHERE k.type = 'UQ'
ORDER BY 1, 3, 2;
"""
SQL_INDICES = """
SELECT OBJECT_NAME(i.object_id), i.name,
       (SELECT STRING_AGG(COL_NAME(ic.object_id, ic.column_id) + CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE '' END, ', ')
               WITHIN GROUP (ORDER BY ic.key_ordinal)
        FROM sys.index_columns ic WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0),
       ISNULL((SELECT STRING_AGG(COL_NAME(ic.object_id, ic.column_id), ', ')
        FROM sys.index_columns ic WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1), '-'),
       CASE WHEN i.is_unique = 1 THEN 'Sí' ELSE 'No' END, ISNULL(i.filter_definition, '-')
FROM sys.indexes i
WHERE i.type = 2 AND i.is_primary_key = 0 AND i.is_unique_constraint = 0 AND OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
ORDER BY 1, 2;
"""
SQL_OBJETOS = """
SELECT 'P', name FROM sys.procedures
UNION ALL SELECT 'V', name FROM sys.views
UNION ALL SELECT 'T', name + ' (sobre ' + OBJECT_NAME(parent_id) + ')' FROM sys.triggers
UNION ALL SELECT 'F', name FROM sys.objects WHERE type IN ('IF', 'FN', 'TF')
ORDER BY 1, 2;
"""

# ================================================================= textos
TABLAS = {
    "Rol": "Roles del sistema: Administrador y Cliente.",
    "Usuario": "Credencial de acceso. Guarda solo el hash de la contraseña, nunca el texto.",
    "Cliente": "Datos personales del comprador. Relación 1:1 con Usuario.",
    "ZonaEnvio": "Tabla de zonas con la tarifa de envío y los días estimados de entrega.",
    "Direccion": "Direcciones de entrega de cada cliente; cada una pertenece a una zona de envío.",
    "Marca": "Catálogo de marcas.",
    "Categoria": "Catálogo de categorías de producto.",
    "Producto": "Producto a la venta, con su precio y costo vigentes.",
    "ProductoImagen": "Imágenes (URL o ruta) de un producto; una sola es la principal.",
    "Inventario": "Existencia actual y mínimo de cada producto. Relación 1:1 con Producto.",
    "MovimientoInventario": "Libro de entradas, salidas y ajustes. Es inmutable: no se edita ni se borra.",
    "Carrito": "Carrito persistente; uno por cliente.",
    "DetalleCarrito": "Productos y cantidades dentro de un carrito.",
    "Promocion": "Descuento por porcentaje o monto fijo, con período de vigencia.",
    "PromocionProducto": "Relación N:M entre promociones y productos.",
    "EstadoPedido": "Catálogo de estados del pedido.",
    "TransicionEstado": "Transiciones permitidas entre estados (regla de negocio guardada como datos).",
    "MetodoPago": "Formas de pago simuladas y si aprueban de inmediato.",
    "Pedido": "Encabezado del pedido con sus importes históricos.",
    "DetallePedido": "Líneas del pedido con precio, descuento y costo del momento de la compra.",
    "HistorialEstadoPedido": "Cada cambio de estado de un pedido, con fecha y usuario. Lo llena un trigger.",
    "Pago": "Pago simulado del pedido (uno por pedido).",
    "Envio": "Envío simulado: zona, número de guía, fechas de despacho y entrega.",
    "Resena": "Calificación de 1 a 5 y comentario de un cliente sobre un producto.",
    "AuditoriaPrecio": "Auditoría de cambios de precio. La llena un trigger.",
}

COLUMNAS = {
    "Activo": "Estado lógico: 1 activo, 0 inactivo (eliminación lógica).",
    "Nombre": "Nombre.", "Apellidos": "Apellidos del cliente.", "Descripcion": "Descripción.",
    "RolId": "Identificador del rol.", "UsuarioId": "Usuario de la aplicación.", "ClienteId": "Cliente.",
    "Correo": "Correo electrónico; es el nombre de usuario.", "HashContrasena": "Hash scrypt de la contraseña.",
    "FechaCreacion": "Fecha y hora de creación.", "UltimoAcceso": "Último ingreso al sistema.",
    "Identificacion": "Número de identificación del cliente.", "Telefono": "Teléfono de contacto.",
    "FechaRegistro": "Fecha de registro del cliente.", "ZonaEnvioId": "Zona de envío.",
    "Tarifa": "Costo de envío de la zona, en colones.", "DiasEstimados": "Días hábiles estimados de entrega.",
    "DireccionId": "Dirección de entrega.", "Alias": "Nombre corto de la dirección (Casa, Oficina).",
    "Provincia": "Provincia.", "Canton": "Cantón.", "Distrito": "Distrito.", "Detalle": "Señas exactas.",
    "Predeterminada": "1 si es la dirección por defecto del cliente.",
    "MarcaId": "Marca.", "PaisOrigen": "País de origen de la marca.", "CategoriaId": "Categoría.",
    "ProductoId": "Producto.", "SKU": "Código único del producto.", "Especificaciones": "Características técnicas (texto descriptivo).",
    "Precio": "Precio de venta vigente, en colones.", "Costo": "Costo vigente, en colones.",
    "Destacado": "1 si se muestra en la sección de destacados.", "ImagenId": "Identificador de la imagen.",
    "Url": "URL o ruta de la imagen.", "EsPrincipal": "1 si es la imagen principal del producto.", "Orden": "Orden de presentación.",
    "Existencia": "Unidades disponibles. Nunca negativa.", "StockMinimo": "Mínimo de inventario; por debajo genera alerta.",
    "FechaActualizacion": "Fecha del último cambio.", "CarritoId": "Carrito.", "Cantidad": "Cantidad de unidades.",
    "FechaAgregado": "Fecha en que se agregó la línea.", "PromocionId": "Promoción.",
    "TipoDescuento": "P = porcentaje, M = monto fijo.", "Valor": "Porcentaje o monto del descuento.",
    "FechaInicio": "Primer día de vigencia.", "FechaFin": "Último día de vigencia.",
    "EstadoId": "Estado del pedido.", "EsFinal": "1 si el estado no admite más cambios.",
    "EstadoOrigenId": "Estado de partida.", "EstadoDestinoId": "Estado de llegada permitido.",
    "MetodoPagoId": "Método de pago.", "AprobacionInmediata": "1 si el pago simulado se aprueba en el checkout.",
    "PedidoId": "Pedido.", "FechaPedido": "Fecha y hora de la compra.",
    "Subtotal": "Suma de cantidad por precio histórico, antes de descuentos.",
    "DescuentoTotal": "Suma de los descuentos aplicados.", "CostoEnvio": "Tarifa de envío cobrada en el pedido.",
    "Total": "Subtotal - DescuentoTotal + CostoEnvio (columna calculada).",
    "PrecioUnitario": "Precio de venta histórico de la línea.", "DescuentoUnitario": "Descuento histórico por unidad.",
    "CostoUnitario": "Costo histórico por unidad (para rentabilidad).",
    "TotalLinea": "Cantidad por (PrecioUnitario - DescuentoUnitario) (columna calculada).",
    "HistorialId": "Identificador del registro de historial.", "EstadoAnteriorId": "Estado previo (NULL al crear el pedido).",
    "EstadoNuevoId": "Estado al que pasó el pedido.", "Fecha": "Fecha y hora del registro.",
    "UsuarioBD": "Inicio de sesión de SQL Server que ejecutó el cambio.", "Comentario": "Comentario o motivo.",
    "PagoId": "Identificador del pago.", "Monto": "Monto pagado; igual al total del pedido.",
    "Estado": "PENDIENTE, APROBADO, REEMBOLSADO o ANULADO.", "Referencia": "Comprobante simulado, único.",
    "EnvioId": "Identificador del envío.", "NumeroGuia": "Guía del transportista; se asigna al despachar.",
    "FechaDespacho": "Fecha de salida de bodega.", "FechaEntrega": "Fecha de entrega al cliente.",
    "MovimientoId": "Identificador del movimiento.", "Tipo": "ENTRADA, SALIDA o AJUSTE.",
    "ExistenciaResultante": "Existencia que quedó después del movimiento.", "Motivo": "Razón del movimiento.",
    "ResenaId": "Identificador de la reseña.", "Calificacion": "Calificación de 1 a 5.",
    "AuditoriaId": "Identificador del registro de auditoría.", "PrecioAnterior": "Precio antes del cambio.",
    "PrecioNuevo": "Precio después del cambio.",
}
COLUMNAS_ESPECIFICAS = {
    ("MovimientoInventario", "Cantidad"): "Unidades con signo: entrada positiva, salida negativa, ajuste con su signo.",
    ("MovimientoInventario", "PedidoId"): "Pedido que originó el movimiento (venta o reintegro); NULL si es manual.",
    ("DetallePedido", "PromocionId"): "Promoción aplicada a la línea; NULL si no hubo.",
    ("Cliente", "UsuarioId"): "Credencial del cliente (relación 1:1).",
    ("HistorialEstadoPedido", "UsuarioId"): "Usuario de la aplicación que hizo el cambio.",
    ("AuditoriaPrecio", "UsuarioId"): "Usuario de la aplicación que cambió el precio.",
    ("MovimientoInventario", "UsuarioId"): "Usuario que registró el movimiento.",
}

INDICES = {
    "IX_Producto_Categoria": "Catálogo filtrado por categoría, la consulta más frecuente de la tienda. Incluye nombre, precio y marca para no leer la tabla.",
    "IX_Producto_Marca": "Filtro por marca y reportes por marca (R3).",
    "IX_Pedido_Cliente_Fecha": "Historial de pedidos de un cliente ordenado del más reciente al más antiguo; también sirve a R1 y R8.",
    "IX_Pedido_Fecha": "Reportes por rango de fechas (R4, R9, R10): evita recorrer todos los pedidos.",
    "IX_DetallePedido_Producto": "Ventas por producto (R5, R7). La clave primaria empieza por PedidoId y no sirve para buscar por producto.",
    "IX_Movimiento_Producto_Fecha": "Kardex de un producto y conciliación de inventario.",
    "IX_Resena_Producto": "Reseñas y calificación promedio que muestra cada tarjeta del catálogo.",
    "IX_PromocionProducto_Producto": "Buscar las promociones de un producto; la clave primaria empieza por PromocionId.",
    "UX_Direccion_Predeterminada": "Índice único filtrado: como máximo una dirección predeterminada activa por cliente.",
    "UX_ProductoImagen_Principal": "Índice único filtrado: una sola imagen principal por producto.",
    "UX_Envio_NumeroGuia": "Índice único filtrado: la guía no se repite, pero puede estar vacía en varios envíos.",
}

# Entidades de cada diagrama y relaciones (notación de Mermaid: || uno, o| cero o uno, o{ cero o muchos, |{ uno o muchos)
DIAGRAMAS = [
    ("Clientes, acceso y carrito",
     ["Rol", "Usuario", "Cliente", "ZonaEnvio", "Direccion", "Carrito", "DetalleCarrito", "Resena"],
     ["Rol ||--o{ Usuario : asigna", "Usuario ||--o| Cliente : identifica", "Cliente ||--o{ Direccion : registra",
      "ZonaEnvio ||--o{ Direccion : cubre", "Cliente ||--o| Carrito : posee", "Carrito ||--o{ DetalleCarrito : contiene",
      "Cliente ||--o{ Resena : escribe"]),
    ("Catálogo, inventario y promociones",
     ["Marca", "Categoria", "Producto", "ProductoImagen", "Inventario", "MovimientoInventario", "Promocion",
      "PromocionProducto", "AuditoriaPrecio"],
     ["Marca ||--o{ Producto : fabrica", "Categoria ||--o{ Producto : clasifica", "Producto ||--o{ ProductoImagen : muestra",
      "Producto ||--|| Inventario : almacena", "Producto ||--o{ MovimientoInventario : registra",
      "Promocion ||--o{ PromocionProducto : incluye", "Producto ||--o{ PromocionProducto : participa",
      "Producto ||--o{ AuditoriaPrecio : audita"]),
    ("Pedidos, pagos y envíos",
     ["Pedido", "DetallePedido", "EstadoPedido", "TransicionEstado", "HistorialEstadoPedido", "MetodoPago", "Pago", "Envio"],
     ["EstadoPedido ||--o{ Pedido : clasifica", "Pedido ||--|{ DetallePedido : contiene",
      "EstadoPedido ||--o{ TransicionEstado : permite",
      "Pedido ||--o{ HistorialEstadoPedido : registra", "Pedido ||--o| Pago : cobra", "MetodoPago ||--o{ Pago : usa",
      "Pedido ||--o| Envio : despacha"]),
]
RELACIONES_ENTRE_DIAGRAMAS = [
    ("Cliente", "Pedido", "1 : N", "Un cliente hace cero o muchos pedidos; cada pedido es de un cliente."),
    ("Direccion", "Pedido", "1 : N", "Cada pedido se entrega en una dirección del cliente."),
    ("Producto", "DetallePedido", "1 : N", "Un producto aparece en cero o muchas líneas de pedido."),
    ("Producto", "DetalleCarrito", "1 : N", "Un producto puede estar en muchos carritos."),
    ("Producto", "Resena", "1 : N", "Un producto recibe cero o muchas reseñas."),
    ("Promocion", "DetallePedido", "0..1 : N", "La línea guarda la promoción aplicada, si hubo (opcional)."),
    ("Pedido", "MovimientoInventario", "0..1 : N", "Las ventas y reintegros apuntan a su pedido; los movimientos manuales no."),
    ("Usuario", "MovimientoInventario", "1 : N", "Todo movimiento registra quién lo hizo."),
    ("Usuario", "HistorialEstadoPedido", "0..1 : N", "Usuario que cambió el estado (opcional si se hizo fuera de la aplicación)."),
    ("Usuario", "AuditoriaPrecio", "0..1 : N", "Usuario que cambió el precio (opcional)."),
    ("ZonaEnvio", "Envio", "1 : N", "Cada envío pertenece a una zona."),
]

PRUEBAS = [
    ("1", "Compra exitosa y descuento de inventario", "Existencias -2 y -3; pedido Confirmado", "PASA"),
    ("2", "Compra fallida por falta de existencias", "Error 51003; @@TRANCOUNT = 0; sin pedido", "PASA"),
    ("3", "Dos productos, uno sin stock", "Error 51003; ningún inventario afectado", "PASA"),
    ("4a", "Cancelación y reintegro", "Existencia vuelve al valor original; pago REEMBOLSADO", "PASA"),
    ("4b", "Segunda cancelación", "Error 51004; sin reintegro duplicado", "PASA"),
    ("5a / 5b", "Transiciones inválidas", "Error 51004; el estado no cambia", "PASA"),
    ("6", "Cambio de precio", "Catálogo +10 %; importe histórico idéntico", "PASA"),
    ("7a–7d", "Duplicados y valores inválidos", "Errores 51002, 2627 y 547", "PASA"),
    ("8a / 8b", "Triggers con varias filas", "Una fila de auditoría por fila modificada", "PASA"),
    ("9", "Reporte R4 contra consulta directa", "Totales idénticos (₡59 146 750 en 34 pedidos)", "PASA"),
    ("10", "Dos compras simultáneas, stock 1", "Una confirma, la otra recibe 51003; existencia 0", "PASA"),
    ("11a / 11b", "Reglas de inventario", "Errores 51003 y 51006", "PASA"),
    ("12a / 12b", "Reglas de reseñas", "Errores 51002 y 51006", "PASA"),
    ("13", "Conciliación de inventario", "0 diferencias; 0 existencias negativas", "PASA"),
]


def tabla(encabezados, filas, clases="") -> str:
    cuerpo = "".join("<tr>" + "".join(f"<td>{c}</td>" for c in f) + "</tr>" for f in filas)
    return (f'<table class="{clases}"><thead><tr>' + "".join(f"<th>{h}</th>" for h in encabezados)
            + f"</tr></thead><tbody>{cuerpo}</tbody></table>")


def mermaid(entidades, relaciones, columnas) -> str:
    lineas = ["erDiagram"]
    for nombre in entidades:
        lineas.append(f"    {nombre} {{")
        for col in columnas[nombre]:
            tipo = col["tipo"].split("(")[0]
            marca = "PK, FK" if col["pk"] and col["fk"] else "PK" if col["pk"] else "FK" if col["fk"] else ""
            nota = ' "calculada"' if col["extra"] == "CALCULADA" else ' "opcional"' if col["nulo"] == "Sí" else ""
            lineas.append(f"        {tipo} {col['nombre']} {marca}".rstrip() + nota)
        lineas.append("    }")
    lineas += [f"    {r}" for r in relaciones]
    return "\n".join(lineas)


def main() -> None:
    columnas: dict[str, list[dict]] = {}
    for t, c, tipo, nulo, defecto, pk, fk, extra in consultar(SQL_COLUMNAS):
        columnas.setdefault(t, []).append(dict(nombre=c, tipo=tipo, nulo=nulo, defecto=defecto.strip("-"),
                                               pk=pk == "PK", fk=fk.strip("-"), extra=extra.strip("-")))
    restricciones: dict[str, list] = {}
    for t, nombre, clase, definicion in consultar(SQL_CHECKS):
        restricciones.setdefault(t, []).append((nombre, clase, definicion))
    indices = consultar(SQL_INDICES)
    objetos: dict[str, list[str]] = {}
    for clase, nombre in consultar(SQL_OBJETOS):
        objetos.setdefault(clase, []).append(nombre)

    faltan = [t for t in columnas if t not in TABLAS]
    if faltan:
        raise SystemExit(f"Faltan descripciones de tablas: {faltan}")

    # ---------- diccionario de datos
    diccionario = []
    for t in sorted(columnas, key=lambda n: list(TABLAS).index(n)):
        filas = []
        for col in columnas[t]:
            llave = " ".join(x for x in ("PK" if col["pk"] else "", f"FK → {col['fk']}" if col["fk"] else "") if x)
            defecto = col["defecto"].strip("()") if col["defecto"] else ""
            if col["extra"]:
                defecto = (defecto + " " + col["extra"]).strip()
            descripcion = COLUMNAS_ESPECIFICAS.get((t, col["nombre"])) or COLUMNAS.get(col["nombre"], "")
            filas.append([f"<b>{e(col['nombre'])}</b>", e(col["tipo"]), col["nulo"], e(llave), e(defecto), e(descripcion)])
        reglas = "".join(f"<li><code>{e(n)}</code> ({c}): {e(d)}</li>" for n, c, d in restricciones.get(t, []))
        diccionario.append(f'<div class="entidad"><h3>{e(t)}</h3><p>{e(TABLAS[t])}</p>'
                           + tabla(["Columna", "Tipo", "Nulo", "Llave", "Defecto / generación", "Descripción"], filas, "dic")
                           + (f'<ul class="reglas">{reglas}</ul>' if reglas else "") + "</div>")

    filas_indices = [[f"<code>{e(n)}</code>", e(t), e(claves), e(incluidas), unico, e(filtro), e(INDICES.get(n, ""))]
                     for t, n, claves, incluidas, unico, filtro in indices]

    diagramas = "".join(
        f'<h3>4.{i}. {e(titulo)}</h3><pre class="mermaid">{e(mermaid(entidades, relaciones, columnas))}</pre>'
        for i, (titulo, entidades, relaciones) in enumerate(DIAGRAMAS, 1))

    procedimientos = objetos.get("P", [])
    grupos: dict[str, list[str]] = {}
    for p in procedimientos:
        grupos.setdefault(p.split("_")[1], []).append(p)
    lista_procs = "".join(f"<tr><td><b>{e(g)}</b></td><td>{len(ps)}</td><td>{e(', '.join(x.split('_', 2)[2] for x in ps))}</td></tr>"
                          for g, ps in sorted(grupos.items()))

    integrantes = "".join(f"<li>{e(i)}</li>" for i in INTEGRANTES)
    documento = PLANTILLA.format(
        institucion=e(INSTITUCION), curso=e(CURSO), profesor=e(PROFESOR), grupo=e(GRUPO), integrantes=integrantes,
        fecha=e(FECHA_ENTREGA), n_tablas=len(columnas), n_procs=len(procedimientos), n_vistas=len(objetos.get("V", [])),
        n_triggers=len(objetos.get("T", [])), n_indices=len(indices), diagramas=diagramas,
        relaciones=tabla(["Entidad (1)", "Entidad (N)", "Cardinalidad", "Lectura"], [[e(x) for x in r] for r in RELACIONES_ENTRE_DIAGRAMAS]),
        diccionario="".join(diccionario),
        indices=tabla(["Índice", "Tabla", "Columnas clave", "Columnas incluidas", "Único", "Filtro", "Justificación"], filas_indices, "dic"),
        procs=lista_procs, vistas=", ".join(f"<code>{e(v)}</code>" for v in objetos.get("V", [])),
        triggers="".join(f"<li><code>{e(t)}</code></li>" for t in objetos.get("T", [])),
        funciones=", ".join(f"<code>{e(f)}</code>" for f in objetos.get("F", [])),
        pruebas=tabla(["Prueba", "Caso", "Resultado esperado y obtenido", "Estado"], [[e(x) for x in p] for p in PRUEBAS]))

    destino = RAIZ / "docs"
    destino.mkdir(exist_ok=True)
    archivo_html = destino / "Documento_Diseno.html"
    archivo_html.write_text(documento, encoding="utf-8")
    print("HTML:", archivo_html)

    navegador = next((p for p in (shutil.which("chrome"), shutil.which("msedge"),
                                  r"C:\Program Files\Google\Chrome\Application\chrome.exe",
                                  r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe") if p and Path(p).exists()), None)
    if not navegador:
        print("No se encontró Chrome ni Edge: abra el HTML y use Imprimir > Guardar como PDF.")
        return
    archivo_pdf = destino / "Documento_Diseno.pdf"
    with tempfile.TemporaryDirectory() as perfil:
        subprocess.run([navegador, "--headless=new", "--disable-gpu", f"--user-data-dir={perfil}", "--no-pdf-header-footer",
                        "--virtual-time-budget=90000", f"--print-to-pdf={archivo_pdf}", archivo_html.as_uri()],
                       check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    print("PDF:", archivo_pdf if archivo_pdf.exists() else "no se pudo generar; imprima el HTML desde el navegador.")


PLANTILLA = """<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>TiendaTech · Documento de diseño</title>
<style>
  @page {{ size: A4; margin: 18mm 15mm; }}
  body {{ font-family: "Segoe UI", Arial, sans-serif; font-size: 10.5pt; line-height: 1.45; color: #1b2430; max-width: 185mm; margin: 0 auto; padding: 0 4mm; }}
  h1 {{ font-size: 19pt; color: #0f2338; border-bottom: 2px solid #0b5cab; padding-bottom: 4px; margin-top: 26px; break-before: page; }}
  h2 {{ font-size: 13pt; color: #0b5cab; margin-top: 18px; }}
  h3 {{ font-size: 11pt; margin: 14px 0 4px; }}
  p, li {{ text-align: justify; }}
  code {{ background: #eef1f5; padding: 0 3px; border-radius: 3px; font-size: 9pt; }}
  table {{ border-collapse: collapse; width: 100%; margin: 6px 0 10px; font-size: 9pt; }}
  th {{ background: #0f2338; color: #fff; text-align: left; padding: 4px 6px; }}
  td {{ border: 1px solid #cfd6de; padding: 3px 6px; vertical-align: top; }}
  tr {{ break-inside: avoid; }}
  table.dic {{ font-size: 8.3pt; }}
  .entidad {{ break-inside: avoid-page; margin-bottom: 10px; }}
  .reglas {{ font-size: 8.3pt; margin: 2px 0 0; padding-left: 16px; }}
  .reglas li {{ text-align: left; }}
  .portada {{ height: 250mm; display: flex; flex-direction: column; justify-content: space-between; text-align: center; }}
  .portada h1 {{ border: 0; font-size: 30pt; break-before: auto; margin: 0; }}
  .portada .sub {{ font-size: 15pt; color: #0b5cab; }}
  .portada ul {{ list-style: none; padding: 0; font-size: 12pt; }}
  .portada li {{ text-align: center; }}
  .mermaid {{ text-align: center; break-inside: avoid; margin: 6px 0 14px; }}
  .nota {{ background: #f0f6fd; border-left: 4px solid #0b5cab; padding: 6px 10px; margin: 8px 0; }}
  .indice li {{ text-align: left; }}
</style>
</head>
<body>

<section class="portada">
  <div><p style="font-size:14pt">{institucion}</p><p>{curso} · {grupo}</p></div>
  <div>
    <p class="sub">Proyecto Programado II</p>
    <h1>TiendaTech</h1>
    <p class="sub">Sistema de comercio electrónico con Microsoft SQL Server</p>
    <p>Documento de diseño</p>
  </div>
  <div><p><b>Integrantes</b></p><ul>{integrantes}</ul><p>Profesor: {profesor}</p><p>{fecha}</p></div>
</section>

<h1>Contenido</h1>
<ol class="indice">
  <li>Descripción del negocio</li><li>Reglas de negocio</li><li>Modelo de datos</li><li>Diagrama entidad-relación</li>
  <li>Normalización</li><li>Diccionario de datos</li><li>Índices</li><li>Decisiones de diseño</li>
  <li>Programación en la base de datos</li><li>Pruebas y evidencias</li>
</ol>
<p class="nota">La base tiene {n_tablas} tablas, {n_procs} procedimientos almacenados, {n_vistas} vistas, {n_triggers} triggers
y {n_indices} índices no agrupados. El diccionario de datos, las restricciones y los índices de este documento se generan
leyendo el catálogo de la base instalada, por lo que coinciden con los scripts entregados.</p>

<h1>1. Descripción del negocio</h1>
<p><b>TiendaTech</b> es una tienda en línea de tecnología que vende laptops, celulares, tabletas, monitores, periféricos,
audio, almacenamiento, relojes inteligentes y accesorios de diez marcas. Vende a todo el país y cobra el envío según la
zona de entrega. Los precios están en colones.</p>
<p>Hay dos tipos de usuario. El <b>cliente</b> consulta el catálogo, administra su perfil y sus direcciones, llena un
carrito que se conserva entre sesiones, compra, revisa el historial de sus pedidos, los cancela mientras no se hayan
enviado y reseña los productos que recibió. El <b>administrador</b> mantiene los catálogos, las promociones y el
inventario, hace avanzar los pedidos por sus estados y consulta los reportes.</p>
<p>El pago, el envío y los correos son simulados, pero su estado queda guardado en la base: cada pedido tiene un pago con
referencia y estado, y un envío con zona, número de guía y fechas.</p>

<h1>2. Reglas de negocio</h1>
<h2>Usuarios y clientes</h2>
<ul>
  <li>El correo identifica al usuario y no se repite. Cada usuario tiene un solo rol.</li>
  <li>La contraseña nunca se guarda: la aplicación calcula un hash scrypt y la base conserva solo ese hash.</li>
  <li>La identificación del cliente no se repite. Un cliente tiene como máximo una dirección predeterminada.</li>
  <li>Un cliente o un producto con historial no se borra: se desactiva.</li>
</ul>
<h2>Catálogo y promociones</h2>
<ul>
  <li>El SKU es único. El precio es mayor que cero y el costo no es negativo.</li>
  <li>La tienda solo muestra productos activos cuya marca y categoría estén activas.</li>
  <li>Una promoción descuenta un porcentaje (hasta 100) o un monto fijo, entre dos fechas; la fecha final no puede ser
      anterior a la inicial.</li>
  <li><b>Regla de combinación:</b> las promociones no se acumulan. Si un producto está en varias promociones vigentes se
      aplica solo la de mayor descuento, y el descuento nunca supera el precio, así que no hay importes negativos.</li>
  <li>El envío cuesta la tarifa de la zona de la dirección de entrega y se suma al total.</li>
</ul>
<h2>Carrito y compra</h2>
<ul>
  <li>Cada cliente tiene un carrito persistente. Un producto aparece en una sola línea; la cantidad es mayor que cero y
      no puede superar la existencia.</li>
  <li>La confirmación del pedido es una sola transacción: valida existencias, registra encabezado y detalle, descuenta
      inventario, registra los movimientos, el pago y el envío, y vacía el carrito. Si algo falla no queda nada guardado.</li>
  <li>El detalle guarda el precio, el descuento y el costo del momento. Un cambio posterior en el catálogo no altera los
      pedidos anteriores.</li>
  <li>Con tarjeta el pago simulado se aprueba de inmediato y el pedido queda <i>Confirmado</i>; con SINPE Móvil o
      transferencia queda <i>Pendiente</i> hasta que el administrador confirme el pago.</li>
</ul>
<h2>Estados y cancelación</h2>
<table>
  <thead><tr><th>Estado actual</th><th>Puede pasar a</th></tr></thead>
  <tbody>
    <tr><td>Pendiente</td><td>Confirmado, Cancelado</td></tr>
    <tr><td>Confirmado</td><td>En preparación, Cancelado</td></tr>
    <tr><td>En preparación</td><td>Enviado, Cancelado</td></tr>
    <tr><td>Enviado</td><td>Entregado</td></tr>
    <tr><td>Entregado, Cancelado</td><td>Ninguno (estados finales)</td></tr>
  </tbody>
</table>
<ul>
  <li>Cada cambio de estado queda en el historial con fecha, hora y usuario.</li>
  <li>La cancelación solo es posible antes del envío. Devuelve las existencias una única vez y deja el pago como
      reembolsado o anulado. Un pedido ya cancelado no se puede volver a cancelar.</li>
  <li>El cliente solo cancela sus propios pedidos; el administrador puede cancelar cualquiera.</li>
</ul>
<h2>Inventario, reseñas y auditoría</h2>
<ul>
  <li>La existencia nunca es negativa y solo cambia por un movimiento (entrada, salida o ajuste) que registra cantidad,
      fecha, usuario y motivo. La existencia siempre es igual a la suma de los movimientos.</li>
  <li>Los movimientos no se modifican ni se borran; un error se corrige con un ajuste.</li>
  <li>Un producto cuya existencia es menor que su mínimo aparece en la alerta del panel.</li>
  <li>Un cliente escribe como máximo una reseña por producto, con calificación de 1 a 5, y solo de productos que compró
      y recibió.</li>
  <li>Todo cambio de precio queda auditado con el valor anterior, el nuevo, la fecha y el usuario.</li>
  <li>Un pedido cancelado no cuenta como venta en ningún reporte.</li>
</ul>

<h1>3. Modelo de datos</h1>
<p>El modelo tiene {n_tablas} tablas agrupadas en tres áreas: clientes y acceso; catálogo, inventario y promociones; y
pedidos, pagos y envíos. Cubre todas las entidades mínimas del enunciado:</p>
<table>
  <thead><tr><th>Concepto del enunciado</th><th>Tabla o tablas</th></tr></thead>
  <tbody>
    <tr><td>Cliente, Usuario/Credencial, Rol</td><td>Cliente, Usuario, Rol</td></tr>
    <tr><td>Dirección</td><td>Direccion, ZonaEnvio</td></tr>
    <tr><td>Marca, Categoría, Producto, Imagen</td><td>Marca, Categoria, Producto, ProductoImagen</td></tr>
    <tr><td>Inventario y sus movimientos</td><td>Inventario, MovimientoInventario</td></tr>
    <tr><td>Carrito y detalle</td><td>Carrito, DetalleCarrito</td></tr>
    <tr><td>Pedido y detalle</td><td>Pedido, DetallePedido</td></tr>
    <tr><td>Estado e historial del pedido</td><td>EstadoPedido, TransicionEstado, HistorialEstadoPedido</td></tr>
    <tr><td>Método de pago, pago simulado, envío</td><td>MetodoPago, Pago, Envio</td></tr>
    <tr><td>Promoción</td><td>Promocion, PromocionProducto</td></tr>
    <tr><td>Reseña y auditoría</td><td>Resena, AuditoriaPrecio</td></tr>
  </tbody>
</table>

<h1>4. Diagrama entidad-relación</h1>
<p>El diagrama se presenta en tres partes para que sea legible. Cada entidad muestra sus columnas con el tipo, la marca
PK o FK y la palabra «opcional» cuando admite nulos. Notación de las líneas: <code>||</code> exactamente uno,
<code>o|</code> cero o uno, <code>o{{</code> cero o muchos, <code>|{{</code> uno o muchos.</p>
{diagramas}
<h3>4.4. Relaciones entre las tres partes</h3>
{relaciones}

<h1>5. Normalización</h1>
<h2>Primera forma normal (1FN)</h2>
<p>Todas las tablas tienen llave primaria y cada columna guarda un solo valor. Los grupos repetitivos se separaron en
tablas propias: las líneas del pedido (<code>DetallePedido</code>), las líneas del carrito (<code>DetalleCarrito</code>),
las imágenes de un producto (<code>ProductoImagen</code>), las direcciones de un cliente (<code>Direccion</code>) y los
productos de una promoción (<code>PromocionProducto</code>). No hay columnas del tipo «Imagen1, Imagen2» ni listas
separadas por comas que se consulten por elemento.</p>
<h2>Segunda forma normal (2FN)</h2>
<p>Las tablas con llave compuesta son <code>DetallePedido</code> (PedidoId, ProductoId), <code>DetalleCarrito</code>
(CarritoId, ProductoId), <code>PromocionProducto</code> y <code>TransicionEstado</code>. En todas, cada atributo depende
de la llave completa: la cantidad y el precio histórico de una línea dependen del pedido <i>y</i> del producto. El nombre
del producto o la fecha del pedido, que dependen de una sola parte de la llave, están en <code>Producto</code> y en
<code>Pedido</code>, no en el detalle.</p>
<h2>Tercera forma normal (3FN)</h2>
<p>Ningún atributo depende de otro que no sea llave:</p>
<ul>
  <li>El nombre de la marca y de la categoría están en sus tablas; <code>Producto</code> solo guarda las llaves foráneas.</li>
  <li>La tarifa de envío depende de la zona y no de la dirección, por eso está en <code>ZonaEnvio</code>.</li>
  <li>El nombre del estado está en <code>EstadoPedido</code> y el del método de pago en <code>MetodoPago</code>.</li>
  <li>Los datos de acceso (correo, hash, rol) están en <code>Usuario</code> y los personales en <code>Cliente</code>.</li>
  <li>La existencia no es un atributo de <code>Producto</code>: está en <code>Inventario</code>, con su propio ciclo de
      actualización y bloqueo.</li>
</ul>
<h2>Desnormalizaciones justificadas</h2>
<table>
  <thead><tr><th>Dato</th><th>Por qué se guarda</th><th>Cómo se mantiene coherente</th></tr></thead>
  <tbody>
    <tr><td><code>DetallePedido.PrecioUnitario</code>, <code>DescuentoUnitario</code>, <code>CostoUnitario</code></td>
        <td>No es redundancia: es un hecho histórico. El precio del catálogo cambia y el pedido debe conservar lo que se cobró.</td>
        <td>Se copian una sola vez, dentro de la transacción del checkout.</td></tr>
    <tr><td><code>Pedido.Subtotal</code>, <code>DescuentoTotal</code>, <code>CostoEnvio</code></td>
        <td>Se podrían calcular sumando el detalle, pero el pedido es un documento que no debe cambiar y se lista con mucha frecuencia.</td>
        <td>Se calculan en el checkout y nunca se actualizan. La prueba 1 y el script de datos verifican que coincidan con el detalle.</td></tr>
    <tr><td><code>Pedido.Total</code>, <code>DetallePedido.TotalLinea</code></td>
        <td>Valores derivados de uso constante.</td>
        <td>Son columnas calculadas persistidas: las mantiene el motor y no pueden quedar incoherentes.</td></tr>
    <tr><td><code>Inventario.Existencia</code></td>
        <td>Es igual a la suma de los movimientos, pero el checkout necesita leerla y bloquearla en una sola fila para evitar la sobreventa.</td>
        <td>Solo cambia junto con su movimiento, en la misma transacción. El procedimiento de conciliación y la prueba 13 comprueban la igualdad.</td></tr>
    <tr><td><code>MovimientoInventario.ExistenciaResultante</code></td>
        <td>Permite leer el kardex sin recalcular saldos acumulados.</td>
        <td>Se escribe una vez y el movimiento es inmutable (trigger).</td></tr>
    <tr><td><code>Direccion.Provincia</code>, <code>Canton</code>, <code>Distrito</code></td>
        <td>Se guardan como texto y no como catálogos geográficos: el negocio solo necesita la zona de envío, que sí está normalizada.</td>
        <td>La regla que importa (la tarifa) depende de <code>ZonaEnvioId</code>.</td></tr>
  </tbody>
</table>

<h1>6. Diccionario de datos</h1>
<p>Para cada tabla se indican sus columnas, tipo, si admite nulos, llaves, valor por defecto y descripción, seguidas de
sus restricciones CHECK y UNIQUE.</p>
{diccionario}

<h1>7. Índices</h1>
<p>Además de los índices que crean las llaves primarias y las restricciones UNIQUE, se definieron {n_indices} índices no
agrupados. Ocho responden a consultas frecuentes y tres son índices únicos filtrados que hacen cumplir una regla de
negocio.</p>
{indices}
<h2>Evidencia de utilidad</h2>
<p>El script <code>sql/09_evidencia_indices.sql</code> carga dentro de una transacción un volumen temporal de 40 000
pedidos y 120 000 líneas, ejecuta cada consulta forzando el recorrido del índice agrupado y luego con el índice no
agrupado, y revierte todo. Lecturas lógicas medidas con <code>SET STATISTICS IO ON</code>:</p>
<table>
  <thead><tr><th>Consulta</th><th>Índice</th><th>Sin el índice</th><th>Con el índice</th></tr></thead>
  <tbody>
    <tr><td>Historial de pedidos de un cliente</td><td><code>IX_Pedido_Cliente_Fecha</code></td><td>324 lecturas</td><td>2 lecturas</td></tr>
    <tr><td>Pedidos de una semana</td><td><code>IX_Pedido_Fecha</code></td><td>324</td><td>6</td></tr>
    <tr><td>Ventas de un producto</td><td><code>IX_DetallePedido_Producto</code></td><td>917</td><td>19</td></tr>
    <tr><td>Catálogo de una categoría</td><td><code>IX_Producto_Categoria</code></td><td>5</td><td>2</td></tr>
  </tbody>
</table>
<p>En SSMS, con el plan de ejecución real activado, la primera variante muestra un <i>Clustered Index Scan</i> y la segunda
un <i>Index Seek</i>.</p>

<h1>8. Decisiones de diseño</h1>
<h2>Política de eliminación</h2>
<ul>
  <li><b>Eliminación lógica</b> (columna <code>Activo</code>) en clientes, usuarios, productos, marcas, categorías,
      promociones, direcciones y reseñas. Lo desactivado deja de mostrarse, pero el historial lo conserva.</li>
  <li><b>Eliminación física</b> solo de marcas y categorías sin productos, líneas del carrito, imágenes y productos de
      una promoción, que no tienen historial.</li>
  <li>Todas las llaves foráneas usan <code>NO ACTION</code>: la base impide borrar un registro referenciado. No se usa
      borrado en cascada.</li>
  <li>Pedidos, pagos, movimientos de inventario y auditoría nunca se borran.</li>
</ul>
<h2>Tipos de datos</h2>
<ul>
  <li>Dinero en <code>DECIMAL(12,2)</code> o <code>DECIMAL(14,2)</code>, nunca en tipos de punto flotante.</li>
  <li>Fechas con hora en <code>DATETIME2</code> y vigencias en <code>DATE</code>.</li>
  <li>Texto con tildes en <code>NVARCHAR</code>; códigos como SKU, teléfono o referencia en <code>VARCHAR</code>.</li>
  <li>Indicadores en <code>BIT</code> con valor por defecto.</li>
</ul>
<h2>Transacciones y concurrencia</h2>
<p>El descuento de inventario del checkout es una sola sentencia
<code>UPDATE … SET Existencia = Existencia - Cantidad WHERE Existencia &gt;= Cantidad</code>. Es atómica y bloquea las
filas que modifica: si dos sesiones compran la última unidad, la segunda espera y, cuando la primera confirma, ya no
cumple la condición. El procedimiento compara las filas actualizadas con las líneas del carrito y, si no coinciden, lanza
el error 51003 y revierte todo. La restricción <code>CHECK (Existencia &gt;= 0)</code> es la última barrera. La prueba 10
lo demuestra con dos conexiones simultáneas.</p>
<p>La cancelación y el cambio de estado leen el pedido con <code>UPDLOCK</code> dentro de la transacción, de modo que dos
cancelaciones simultáneas no pueden reintegrar el inventario dos veces.</p>
<h2>Transiciones de estado como datos</h2>
<p>Las transiciones válidas están en la tabla <code>TransicionEstado</code> y no escritas en el código. El procedimiento
solo pregunta si existe la fila (estado actual, estado nuevo); agregar un flujo nuevo es insertar filas.</p>
<h2>Triggers</h2>
<p>Se usan solo donde aportan algo que un procedimiento no garantiza: la auditoría debe registrarse aunque alguien cambie
un precio o un estado con un <code>UPDATE</code> directo desde SSMS. Trabajan con las tablas <code>inserted</code> y
<code>deleted</code> completas, sin variables escalares ni cursores, por lo que funcionan igual con una o con muchas
filas. El usuario de la aplicación les llega por <code>SESSION_CONTEXT</code>. La lógica de compra no está en triggers.</p>
<h2>Seguridad</h2>
<ul>
  <li>La aplicación solo ejecuta procedimientos almacenados y siempre con parámetros; no arma SQL con texto del usuario.</li>
  <li>Opera con el usuario de base de datos <code>app_tiendatech</code>, que solo tiene permiso <code>EXECUTE</code>. Un
      <code>SELECT</code> directo a una tabla le devuelve «permission denied».</li>
  <li>No hay credenciales administrativas en el código: la configuración está en un archivo <code>.env</code> que no se
      versiona.</li>
  <li>El único SQL dinámico está en el reporte R2 (PIVOT con una columna por categoría). Los nombres de columna salen de
      la tabla <code>Categoria</code> y pasan por <code>QUOTENAME</code>; las fechas viajan como parámetros de
      <code>sp_executesql</code>.</li>
</ul>

<h1>9. Programación en la base de datos</h1>
<h2>Procedimientos almacenados ({n_procs})</h2>
<table>
  <thead><tr><th>Grupo</th><th>Cant.</th><th>Procedimientos (prefijo <code>usp_Grupo_</code>)</th></tr></thead>
  <tbody>{procs}</tbody>
</table>
<ul>
  <li><b>Parámetros OUTPUT:</b> todos los procedimientos <code>_Crear</code>, <code>usp_Cliente_Registrar</code>,
      <code>usp_Pedido_Confirmar</code> y <code>usp_Inventario_RegistrarMovimiento</code> devuelven el identificador creado.</li>
  <li><b>Transacciones explícitas</b> con <code>TRY…CATCH</code>, <code>BEGIN TRAN</code>, <code>COMMIT</code>,
      <code>ROLLBACK</code> y <code>THROW</code>: <code>usp_Pedido_Confirmar</code>, <code>usp_Pedido_Cancelar</code>,
      <code>usp_Pedido_CambiarEstado</code>, <code>usp_Inventario_RegistrarMovimiento</code>, <code>usp_Cliente_Registrar</code>,
      <code>usp_Producto_Crear</code> y <code>usp_Producto_Actualizar</code>, entre otros.</li>
  <li><b>Errores de negocio:</b> números 51000 a 51007 con mensajes legibles que la aplicación muestra tal cual.</li>
</ul>
<h2>Vistas, función y triggers</h2>
<p>Vistas: {vistas}. Función: {funciones}.</p>
<ul>{triggers}</ul>
<h2>Reportes</h2>
<table>
  <thead><tr><th>Reporte</th><th>Procedimiento</th><th>Técnica principal</th></tr></thead>
  <tbody>
    <tr><td>R1 Top clientes</td><td><code>usp_Reporte_R1_TopClientes</code></td><td>GROUP BY, HAVING, ROW_NUMBER</td></tr>
    <tr><td>R2 Matriz cliente × categoría</td><td><code>usp_Reporte_R2_MatrizClienteCategoria</code></td><td>PIVOT</td></tr>
    <tr><td>R3 Ventas mensuales por marca</td><td><code>usp_Reporte_R3_VentasMensualesPorMarca</code></td><td>Agregación condicional, LEFT JOIN</td></tr>
    <tr><td>R4 Evolución mensual</td><td><code>usp_Reporte_R4_EvolucionMensual</code></td><td>CTE de calendario, LEFT JOIN</td></tr>
    <tr><td>R5 Productos más vendidos</td><td><code>usp_Reporte_R5_ProductosMasVendidos</code></td><td>RANK</td></tr>
    <tr><td>R6 Inventario crítico</td><td><code>usp_Reporte_R6_InventarioCritico</code></td><td>Vista, subconsulta derivada</td></tr>
    <tr><td>R7 Rentabilidad</td><td><code>usp_Reporte_R7_Rentabilidad</code></td><td>Agregación sobre costo histórico</td></tr>
    <tr><td>R8 Clientes sin compras</td><td><code>usp_Reporte_R8_ClientesSinCompras</code></td><td>NOT EXISTS</td></tr>
    <tr><td>R9 Comparación temporal</td><td><code>usp_Reporte_R9_ComparacionMensual</code></td><td>LAG</td></tr>
    <tr><td>R10 Resumen de pedidos</td><td><code>usp_Reporte_R10_ResumenPedidos</code></td><td>Filtros parametrizados</td></tr>
  </tbody>
</table>
<p>Todos leen la vista <code>vw_VentasDetalle</code>, que excluye los pedidos cancelados y usa el importe histórico del
detalle, así la regla está escrita una sola vez.</p>

<h1>10. Pruebas y evidencias</h1>
<p>Las pruebas están en <code>sql/07_pruebas.sql</code> (una sola ejecución imprime datos esperados, obtenidos y el
resultado) y en <code>pruebas/prueba_concurrencia.py</code>. El README indica cómo reproducirlas y cómo repetirlas desde
la interfaz.</p>
{pruebas}
<p class="nota">Las capturas de pantalla de la ejecución de las pruebas y de los reportes se entregan en la carpeta
<code>docs/evidencias</code>.</p>

<script type="module">
  import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.esm.min.mjs";
  mermaid.initialize({{ startOnLoad: false, theme: "neutral", er: {{ useMaxWidth: true }} }});
  let numero = 0;   // identificadores propios: evita que dos diagramas compartan id
  for (const nodo of document.querySelectorAll("pre.mermaid")) {{
    const {{ svg }} = await mermaid.render("diagrama-er-" + (++numero), nodo.textContent);
    nodo.innerHTML = svg;
  }}
</script>
</body>
</html>
"""

if __name__ == "__main__":
    main()
