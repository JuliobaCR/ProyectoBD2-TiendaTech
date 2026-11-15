"""Pantallas del administrador: panel, catálogos, clientes, promociones, pedidos, inventario, auditoría."""
from flask import Blueprint, abort, redirect, render_template, request, session, url_for
from werkzeug.security import generate_password_hash

import db
from util import ErrorEntrada, decimal, entero, fecha, intentar, marcado, requiere_admin, texto

bp = Blueprint("admin", __name__)


def _uid() -> int:
    return session["uid"]


def _activo_filtro():
    valor = request.args.get("activo")
    return {"1": 1, "0": 0}.get(valor)


# ================================================================ panel
@bp.get("/")
@requiere_admin
def panel():
    return render_template("admin/panel.html", r=db.fila("usp_Admin_Resumen"),
                           bajo_minimo=db.filas("usp_Inventario_BajoMinimo"),
                           por_estado=db.filas("usp_Reporte_R10_PedidosPorEstado"))


# ================================================================ marcas y categorías
# Las dos pantallas son iguales; solo cambian el procedimiento y el segundo campo.
_SIMPLES = {
    "marcas": dict(titulo="Marcas", singular="marca", sp="usp_Marca", id="MarcaId", extra="PaisOrigen", extra_etiqueta="País de origen"),
    "categorias": dict(titulo="Categorías", singular="categoría", sp="usp_Categoria", id="CategoriaId", extra="Descripcion", extra_etiqueta="Descripción"),
}


@bp.get("/<any(marcas, categorias):tipo>")
@requiere_admin
def simples(tipo):
    cfg = _SIMPLES[tipo]
    lista = db.filas(cfg["sp"] + "_Listar", Buscar=texto("q"), Activo=_activo_filtro())
    return render_template("admin/simples.html", cfg=cfg, tipo=tipo, lista=lista)


@bp.post("/<any(marcas, categorias):tipo>")
@requiere_admin
def simples_guardar(tipo):
    cfg = _SIMPLES[tipo]

    def accion():
        registro_id = entero("id")
        operacion = request.form.get("accion")
        if operacion == "eliminar":
            db.ejecutar(cfg["sp"] + "_Eliminar", **{cfg["id"]: registro_id})
            return f"Se eliminó la {cfg['singular']}."
        datos = {"Nombre": texto("nombre", True, "Nombre"), cfg["extra"]: texto("extra")}
        if registro_id:
            db.ejecutar(cfg["sp"] + "_Actualizar", **{cfg["id"]: registro_id}, **datos, Activo=marcado("activo"))
            return "Cambios guardados."
        db.ejecutar_con_salida(cfg["sp"] + "_Crear", cfg["id"], **datos)
        return f"Se creó la {cfg['singular']}."
    intentar(accion, lambda mensaje: mensaje)
    return redirect(url_for("admin.simples", tipo=tipo))


# ================================================================ productos
@bp.get("/productos")
@requiere_admin
def productos():
    lista = db.filas("usp_Producto_ListarAdmin", Buscar=texto("q"), MarcaId=entero("marca"),
                     CategoriaId=entero("categoria"), Activo=_activo_filtro())
    return render_template("admin/productos.html", lista=lista, marcas=db.filas("usp_Marca_Listar"),
                           categorias=db.filas("usp_Categoria_Listar"))


def _datos_producto():
    return dict(SKU=texto("sku", True, "SKU"), Nombre=texto("nombre", True, "Nombre"), Descripcion=texto("descripcion"),
                Especificaciones=texto("especificaciones"), MarcaId=entero("marca_id", True, "Marca"),
                CategoriaId=entero("categoria_id", True, "Categoría"), Precio=decimal("precio", True, "Precio"),
                Costo=decimal("costo", True, "Costo"), StockMinimo=entero("stock_minimo") or 0,
                Destacado=marcado("destacado"), ImagenUrl=texto("imagen_url"), UsuarioId=_uid())


@bp.route("/productos/nuevo", methods=["GET", "POST"])
@requiere_admin
def producto_nuevo():
    if request.method == "POST":
        ok, nuevo_id = intentar(lambda: db.ejecutar_con_salida(
            "usp_Producto_Crear", "ProductoId", **_datos_producto(), StockInicial=entero("stock_inicial") or 0),
            lambda n: f"Producto #{n} creado.")
        if ok:
            return redirect(url_for("admin.producto_editar", producto_id=nuevo_id))
    return render_template("admin/producto_form.html", p=None, f=request.form, imagenes=[],
                           marcas=db.filas("usp_Marca_Listar", Activo=1), categorias=db.filas("usp_Categoria_Listar", Activo=1))


@bp.route("/productos/<int:producto_id>", methods=["GET", "POST"])
@requiere_admin
def producto_editar(producto_id):
    if request.method == "POST":
        operacion = request.form.get("accion")
        if operacion == "estado":
            intentar(lambda: db.ejecutar("usp_Producto_CambiarEstado", ProductoId=producto_id, Activo=marcado("activo")),
                     "Estado del producto actualizado.")
        elif operacion == "imagen":
            intentar(lambda: db.ejecutar("usp_ProductoImagen_Agregar", ProductoId=producto_id, Url=texto("url", True, "URL")),
                     "Imagen agregada.")
        elif operacion == "quitar_imagen":
            intentar(lambda: db.ejecutar("usp_ProductoImagen_Eliminar", ImagenId=entero("imagen_id", True)), "Imagen eliminada.")
        else:
            intentar(lambda: db.ejecutar("usp_Producto_Actualizar", ProductoId=producto_id, **_datos_producto()),
                     "Producto actualizado. Si cambió el precio, quedó registrado en la auditoría.")
        return redirect(url_for("admin.producto_editar", producto_id=producto_id))
    p = db.fila("usp_Producto_Obtener", ProductoId=producto_id)
    if not p:
        abort(404)
    return render_template("admin/producto_form.html", p=p, f={}, imagenes=db.filas("usp_ProductoImagen_Listar", ProductoId=producto_id),
                           marcas=db.filas("usp_Marca_Listar"), categorias=db.filas("usp_Categoria_Listar"))


@bp.post("/productos/ajuste-precios")
@requiere_admin
def ajuste_precios():
    intentar(lambda: db.ejecutar_con_salida("usp_Producto_AjustarPrecioCategoria", "Afectados",
                                            CategoriaId=entero("categoria_id", True, "Categoría"),
                                            Porcentaje=decimal("porcentaje", True, "Porcentaje"), UsuarioId=_uid()),
             lambda n: f"Se actualizó el precio de {n} productos; cada cambio quedó en la auditoría.")
    return redirect(url_for("admin.auditoria"))


# ================================================================ clientes
@bp.get("/clientes")
@requiere_admin
def clientes():
    return render_template("admin/clientes.html", lista=db.filas("usp_Cliente_Listar", Buscar=texto("q"), Activo=_activo_filtro()))


@bp.post("/clientes")
@requiere_admin
def clientes_guardar():
    def accion():
        operacion = request.form.get("accion")
        cliente_id = entero("id")
        if operacion == "estado":
            db.ejecutar("usp_Cliente_CambiarEstado", ClienteId=cliente_id, Activo=marcado("activo"))
            return "Estado del cliente actualizado."
        datos = dict(Nombre=texto("nombre", True, "Nombre"), Apellidos=texto("apellidos", True, "Apellidos"),
                     Identificacion=texto("identificacion", True, "Identificación"), Telefono=texto("telefono"))
        if cliente_id:
            db.ejecutar("usp_Cliente_Actualizar", ClienteId=cliente_id, **datos)
            return "Cliente actualizado."
        clave = request.form.get("clave") or ""
        if len(clave) < 8:
            raise ErrorEntrada("La contraseña temporal debe tener al menos 8 caracteres.")
        db.ejecutar_con_salida("usp_Cliente_Registrar", "ClienteId", Correo=texto("correo", True, "Correo"),
                               HashContrasena=generate_password_hash(clave), **datos)
        return "Cliente creado."
    intentar(accion, lambda mensaje: mensaje)
    return redirect(url_for("admin.clientes"))


# ================================================================ promociones
@bp.get("/promociones")
@requiere_admin
def promociones():
    seleccion = request.args.get("ver", type=int)
    return render_template("admin/promociones.html", lista=db.filas("usp_Promocion_Listar"), seleccion=seleccion,
                           productos_promo=db.filas("usp_Promocion_ListarProductos", PromocionId=seleccion) if seleccion else [],
                           categorias=db.filas("usp_Categoria_Listar", Activo=1),
                           productos=db.filas("usp_Producto_ListarAdmin", Activo=1) if seleccion else [])


@bp.post("/promociones")
@requiere_admin
def promociones_guardar():
    promo_id = entero("id")

    def accion():
        operacion = request.form.get("accion")
        if operacion == "categoria":
            n = db.ejecutar_con_salida("usp_Promocion_AsignarCategoria", "Agregados", PromocionId=promo_id,
                                       CategoriaId=entero("categoria_id", True, "Categoría"))
            return f"Se agregaron {n} productos a la promoción."
        if operacion == "producto":
            db.ejecutar("usp_Promocion_AsignarProducto", PromocionId=promo_id, ProductoId=entero("producto_id", True, "Producto"))
            return "Producto agregado a la promoción."
        if operacion == "quitar":
            db.ejecutar("usp_Promocion_QuitarProducto", PromocionId=promo_id, ProductoId=entero("producto_id", True))
            return "Producto quitado de la promoción."
        datos = dict(Nombre=texto("nombre", True, "Nombre"), TipoDescuento=texto("tipo", True, "Tipo"),
                     Valor=decimal("valor", True, "Valor"), FechaInicio=fecha("inicio", True, "Fecha de inicio"),
                     FechaFin=fecha("fin", True, "Fecha final"))
        if promo_id:
            db.ejecutar("usp_Promocion_Actualizar", PromocionId=promo_id, **datos, Activo=marcado("activo"))
            return "Promoción actualizada."
        db.ejecutar_con_salida("usp_Promocion_Crear", "PromocionId", **datos)
        return "Promoción creada. Ahora asígnele productos."
    intentar(accion, lambda mensaje: mensaje)
    return redirect(url_for("admin.promociones", ver=promo_id) if promo_id else url_for("admin.promociones"))


# ================================================================ pedidos
@bp.get("/pedidos")
@requiere_admin
def pedidos():
    try:
        filtros = dict(EstadoId=entero("estado"), Desde=fecha("desde"), Hasta=fecha("hasta"), Buscar=texto("q"))
    except ErrorEntrada:
        filtros = {}
    return render_template("admin/pedidos.html", lista=db.filas("usp_Reporte_R10_ResumenPedidos", **filtros),
                           estados=db.filas("usp_EstadoPedido_Listar"))


@bp.route("/pedidos/<int:pedido_id>", methods=["GET", "POST"])
@requiere_admin
def pedido(pedido_id):
    if request.method == "POST":
        if request.form.get("accion") == "cancelar":
            intentar(lambda: db.ejecutar("usp_Pedido_Cancelar", PedidoId=pedido_id, UsuarioId=_uid(),
                                         Motivo=texto("motivo", True, "Motivo")),
                     "Pedido cancelado y existencias reintegradas.")
        else:
            intentar(lambda: db.ejecutar("usp_Pedido_CambiarEstado", PedidoId=pedido_id, UsuarioId=_uid(),
                                         NuevoEstadoId=entero("estado_id", True, "Nuevo estado"), Comentario=texto("comentario")),
                     "Estado del pedido actualizado.")
        return redirect(url_for("admin.pedido", pedido_id=pedido_id))
    o = db.fila("usp_Pedido_Obtener", PedidoId=pedido_id)
    if not o:
        abort(404)
    return render_template("admin/pedido.html", o=o, lineas=db.filas("usp_Pedido_Detalle", PedidoId=pedido_id),
                           historial=db.filas("usp_Pedido_Historial", PedidoId=pedido_id),
                           transiciones=db.filas("usp_Pedido_TransicionesDisponibles", PedidoId=pedido_id),
                           estados=db.filas("usp_EstadoPedido_Listar"))


# ================================================================ inventario
@bp.get("/inventario")
@requiere_admin
def inventario():
    try:
        filtros = dict(ProductoId=entero("producto"), Tipo=texto("tipo"), Desde=fecha("desde"), Hasta=fecha("hasta"))
    except ErrorEntrada:
        filtros = {}
    return render_template("admin/inventario.html", productos=db.filas("usp_Producto_ListarAdmin"),
                           bajo_minimo=db.filas("usp_Inventario_BajoMinimo"),
                           movimientos=db.filas("usp_Inventario_Movimientos", **filtros),
                           diferencias=db.filas("usp_Inventario_Conciliacion", SoloDiferencias=1))


@bp.post("/inventario")
@requiere_admin
def inventario_movimiento():
    intentar(lambda: db.ejecutar_con_salida("usp_Inventario_RegistrarMovimiento", "MovimientoId",
                                            ProductoId=entero("producto_id", True, "Producto"), Tipo=texto("tipo", True, "Tipo"),
                                            Cantidad=entero("cantidad", True, "Cantidad"), UsuarioId=_uid(),
                                            Motivo=texto("motivo", True, "Motivo")),
             lambda n: f"Movimiento #{n} registrado.")
    return redirect(url_for("admin.inventario"))


@bp.get("/inventario/conciliacion")
@requiere_admin
def conciliacion():
    return render_template("admin/conciliacion.html", lista=db.filas("usp_Inventario_Conciliacion"))


# ================================================================ auditoría
@bp.get("/auditoria")
@requiere_admin
def auditoria():
    return render_template("admin/auditoria.html", precios=db.filas("usp_Auditoria_Precios"),
                           estados=db.filas("usp_Auditoria_Estados"), categorias=db.filas("usp_Categoria_Listar", Activo=1))
