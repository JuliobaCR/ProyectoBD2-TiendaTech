"""Pantallas del cliente: acceso, catálogo, detalle, carrito, checkout, pedidos, perfil."""
from flask import Blueprint, abort, flash, redirect, render_template, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash

import db
from util import (ROL_ADMIN, ErrorEntrada, decimal, entero, intentar, marcado, requiere_cliente,
                  requiere_sesion, texto)

bp = Blueprint("tienda", __name__)


def _cid() -> int:
    return session["cid"]


# ================================================================ acceso y registro
@bp.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        correo = (request.form.get("correo") or "").strip().lower()
        clave = request.form.get("clave") or ""
        usuario = db.fila("usp_Usuario_ObtenerPorCorreo", Correo=correo) if correo else None
        # El hash se verifica aquí; a SQL Server nunca llega la contraseña.
        if not usuario or not check_password_hash(usuario["HashContrasena"], clave):
            flash("Correo o contraseña incorrectos.", "error")
        elif not usuario["Activo"]:
            flash("La cuenta está desactivada. Contacte a la tienda.", "error")
        else:
            token = session.get("_csrf")
            session.clear()
            session.update(_csrf=token, uid=usuario["UsuarioId"], rol=usuario["RolId"],
                           cid=usuario["ClienteId"], nombre=usuario["NombreCompleto"], correo=usuario["Correo"])
            db.ejecutar("usp_Usuario_RegistrarAcceso", UsuarioId=usuario["UsuarioId"])
            if usuario["RolId"] == ROL_ADMIN:
                return redirect(url_for("admin.panel"))
            destino = request.args.get("siguiente") or ""
            return redirect(destino if destino.startswith("/") and not destino.startswith("//") else url_for("tienda.catalogo"))
    return render_template("login.html")


@bp.post("/salir")
def salir():
    session.clear()
    flash("Sesión cerrada.", "ok")
    return redirect(url_for("tienda.catalogo"))


@bp.route("/registro", methods=["GET", "POST"])
def registro():
    if request.method == "POST":
        def accion():
            clave = request.form.get("clave") or ""
            if len(clave) < 8:
                raise ErrorEntrada("La contraseña debe tener al menos 8 caracteres.")
            if clave != (request.form.get("clave2") or ""):
                raise ErrorEntrada("Las contraseñas no coinciden.")
            return db.ejecutar_con_salida(
                "usp_Cliente_Registrar", "ClienteId",
                Correo=texto("correo", True, "Correo"), HashContrasena=generate_password_hash(clave),
                Nombre=texto("nombre", True, "Nombre"), Apellidos=texto("apellidos", True, "Apellidos"),
                Identificacion=texto("identificacion", True, "Identificación"), Telefono=texto("telefono"))
        ok, _ = intentar(accion, "Cuenta creada. Ya puede iniciar sesión.")
        if ok:
            return redirect(url_for("tienda.login"))
    return render_template("registro.html", f=request.form)


# ================================================================ catálogo
@bp.get("/")
def catalogo():
    filtros = {}
    try:
        filtros = dict(Texto=texto("q"), MarcaId=entero("marca"), CategoriaId=entero("categoria"),
                       PrecioMin=decimal("min", etiqueta="Precio mínimo"), PrecioMax=decimal("max", etiqueta="Precio máximo"),
                       SoloOfertas=marcado("ofertas"), SoloDisponibles=marcado("disponibles"),
                       Orden=request.args.get("orden") or "nombre")
        productos = db.filas("usp_Catalogo_Buscar", **filtros)
    except (ErrorEntrada, db.ErrorBD) as e:
        flash(str(e), "error")
        productos = db.filas("usp_Catalogo_Buscar")
    hay_filtros = any(request.args.get(k) for k in ("q", "marca", "categoria", "min", "max", "ofertas", "disponibles"))
    destacados = ofertas = []
    if not hay_filtros:
        destacados = db.filas("usp_Catalogo_Buscar", SoloDestacados=1)
        ofertas = db.filas("usp_Catalogo_Buscar", SoloOfertas=1, Orden="precio_asc")
    promociones = sorted({o["Promocion"] for o in ofertas if o["Promocion"]})
    return render_template("catalogo.html", productos=productos, destacados=destacados, ofertas=ofertas[:8], promociones=promociones,
                           hay_filtros=hay_filtros,
                           marcas=db.filas("usp_Marca_Listar", Activo=1),
                           categorias=db.filas("usp_Categoria_Listar", Activo=1))


@bp.get("/producto/<int:producto_id>")
def producto(producto_id):
    p = db.fila("usp_Catalogo_Detalle", ProductoId=producto_id)
    if not p:
        abort(404)
    estado_resena = None
    if session.get("cid"):
        estado_resena = db.fila("usp_Resena_Estado", ClienteId=_cid(), ProductoId=producto_id)
    return render_template("producto.html", p=p, estado_resena=estado_resena,
                           imagenes=db.filas("usp_ProductoImagen_Listar", ProductoId=producto_id),
                           resenas=db.filas("usp_Resena_ListarPorProducto", ProductoId=producto_id))


# ================================================================ reseñas
@bp.post("/producto/<int:producto_id>/resena")
@requiere_cliente
def guardar_resena(producto_id):
    def accion():
        calificacion = entero("calificacion", True, "Calificación")
        resena_id = entero("resena_id")
        if resena_id:
            db.ejecutar("usp_Resena_Actualizar", ResenaId=resena_id, ClienteId=_cid(),
                        Calificacion=calificacion, Comentario=texto("comentario"))
        else:
            db.ejecutar_con_salida("usp_Resena_Crear", "ResenaId", ClienteId=_cid(), ProductoId=producto_id,
                                   Calificacion=calificacion, Comentario=texto("comentario"))
    intentar(accion, "Reseña guardada. ¡Gracias por su opinión!")
    return redirect(url_for("tienda.producto", producto_id=producto_id))


@bp.post("/resena/<int:resena_id>/eliminar")
@requiere_sesion
def eliminar_resena(resena_id):
    intentar(lambda: db.ejecutar("usp_Resena_Eliminar", ResenaId=resena_id, UsuarioId=session["uid"]), "Reseña eliminada.")
    return redirect(request.form.get("volver") or url_for("tienda.catalogo"))


# ================================================================ carrito
@bp.get("/carrito")
@requiere_cliente
def carrito():
    return render_template("carrito.html", lineas=db.filas("usp_Carrito_Obtener", ClienteId=_cid()),
                           resumen=db.fila("usp_Carrito_Resumen", ClienteId=_cid()))


@bp.post("/carrito/agregar")
@requiere_cliente
def carrito_agregar():
    producto_id = entero("producto_id", True)
    intentar(lambda: db.ejecutar("usp_Carrito_Agregar", ClienteId=_cid(), ProductoId=producto_id,
                                 Cantidad=entero("cantidad") or 1), "Producto agregado al carrito.")
    return redirect(request.form.get("volver") or url_for("tienda.carrito"))


@bp.post("/carrito/cantidad")
@requiere_cliente
def carrito_cantidad():
    intentar(lambda: db.ejecutar("usp_Carrito_CambiarCantidad", ClienteId=_cid(), ProductoId=entero("producto_id", True),
                                 Cantidad=entero("cantidad", True, "Cantidad")), "Cantidad actualizada.")
    return redirect(url_for("tienda.carrito"))


@bp.post("/carrito/eliminar")
@requiere_cliente
def carrito_eliminar():
    intentar(lambda: db.ejecutar("usp_Carrito_EliminarLinea", ClienteId=_cid(), ProductoId=entero("producto_id", True)),
             "Producto eliminado del carrito.")
    return redirect(url_for("tienda.carrito"))


@bp.post("/carrito/vaciar")
@requiere_cliente
def carrito_vaciar():
    intentar(lambda: db.ejecutar("usp_Carrito_Vaciar", ClienteId=_cid()), "Carrito vaciado.")
    return redirect(url_for("tienda.carrito"))


# ================================================================ checkout
@bp.route("/checkout", methods=["GET", "POST"])
@requiere_cliente
def checkout():
    if request.method == "POST":
        # Toda la compra ocurre dentro de usp_Pedido_Confirmar (una sola transacción).
        ok, pedido_id = intentar(lambda: db.ejecutar_con_salida(
            "usp_Pedido_Confirmar", "PedidoId", ClienteId=_cid(),
            DireccionId=entero("direccion_id", True, "Dirección de entrega"),
            MetodoPagoId=entero("metodo_pago_id", True, "Forma de pago")),
            lambda n: f"¡Pedido #{n} registrado!")
        if ok:
            return redirect(url_for("tienda.pedido", pedido_id=pedido_id))
        return redirect(url_for("tienda.checkout"))

    lineas = db.filas("usp_Carrito_Obtener", ClienteId=_cid())
    if not lineas:
        flash("El carrito está vacío.", "aviso")
        return redirect(url_for("tienda.carrito"))
    direcciones = db.filas("usp_Direccion_ListarPorCliente", ClienteId=_cid())
    direccion_id = request.args.get("direccion", type=int)
    if direccion_id not in [d["DireccionId"] for d in direcciones]:
        direccion_id = direcciones[0]["DireccionId"] if direcciones else None
    return render_template("checkout.html", lineas=lineas, direcciones=direcciones, direccion_id=direccion_id,
                           metodos=db.filas("usp_MetodoPago_Listar"),
                           zonas=db.filas("usp_ZonaEnvio_Listar"),
                           resumen=db.fila("usp_Carrito_Resumen", ClienteId=_cid(), DireccionId=direccion_id))


# ================================================================ pedidos
@bp.get("/pedidos")
@requiere_cliente
def pedidos():
    return render_template("pedidos.html", pedidos=db.filas("usp_Pedido_ListarPorCliente", ClienteId=_cid()))


def _cargar_pedido(pedido_id):
    """El cliente solo ve sus pedidos; el administrador ve todos."""
    cliente = None if session.get("rol") == ROL_ADMIN else _cid()
    encabezado = db.fila("usp_Pedido_Obtener", PedidoId=pedido_id, ClienteId=cliente)
    if not encabezado:
        abort(404)
    return dict(o=encabezado, lineas=db.filas("usp_Pedido_Detalle", PedidoId=pedido_id),
                historial=db.filas("usp_Pedido_Historial", PedidoId=pedido_id))


@bp.get("/pedidos/<int:pedido_id>")
@requiere_cliente
def pedido(pedido_id):
    return render_template("pedido.html", **_cargar_pedido(pedido_id))


@bp.get("/pedidos/<int:pedido_id>/imprimir")
@requiere_sesion
def pedido_imprimir(pedido_id):
    return render_template("pedido_imprimir.html", **_cargar_pedido(pedido_id))


@bp.post("/pedidos/<int:pedido_id>/cancelar")
@requiere_cliente
def pedido_cancelar(pedido_id):
    intentar(lambda: db.ejecutar("usp_Pedido_Cancelar", PedidoId=pedido_id, UsuarioId=session["uid"],
                                 Motivo=texto("motivo", True, "Motivo")),
             "Pedido cancelado. Las existencias fueron reintegradas.")
    return redirect(url_for("tienda.pedido", pedido_id=pedido_id))


# ================================================================ perfil y direcciones
@bp.route("/perfil", methods=["GET", "POST"])
@requiere_cliente
def perfil():
    if request.method == "POST":
        if request.form.get("accion") == "clave":
            def cambiar_clave():
                usuario = db.fila("usp_Usuario_ObtenerPorCorreo", Correo=session["correo"])
                if not check_password_hash(usuario["HashContrasena"], request.form.get("actual") or ""):
                    raise ErrorEntrada("La contraseña actual no es correcta.")
                nueva = request.form.get("nueva") or ""
                if len(nueva) < 8:
                    raise ErrorEntrada("La contraseña nueva debe tener al menos 8 caracteres.")
                if nueva != (request.form.get("nueva2") or ""):
                    raise ErrorEntrada("Las contraseñas nuevas no coinciden.")
                db.ejecutar("usp_Usuario_CambiarContrasena", UsuarioId=session["uid"], HashNuevo=generate_password_hash(nueva))
            intentar(cambiar_clave, "Contraseña actualizada.")
        else:
            def actualizar():
                db.ejecutar("usp_Cliente_Actualizar", ClienteId=_cid(), Nombre=texto("nombre", True, "Nombre"),
                            Apellidos=texto("apellidos", True, "Apellidos"),
                            Identificacion=texto("identificacion", True, "Identificación"), Telefono=texto("telefono"))
                session["nombre"] = f"{texto('nombre')} {texto('apellidos')}"
            intentar(actualizar, "Perfil actualizado.")
        return redirect(url_for("tienda.perfil"))
    return render_template("perfil.html", c=db.fila("usp_Cliente_Obtener", ClienteId=_cid()),
                           direcciones=db.filas("usp_Direccion_ListarPorCliente", ClienteId=_cid()),
                           zonas=db.filas("usp_ZonaEnvio_Listar"),
                           resenas=db.filas("usp_Resena_ListarPorCliente", ClienteId=_cid()))


def _datos_direccion():
    return dict(ZonaEnvioId=entero("zona_id", True, "Zona de envío"), Alias=texto("alias", True, "Alias"),
                Provincia=texto("provincia", True, "Provincia"), Canton=texto("canton", True, "Cantón"),
                Distrito=texto("distrito", True, "Distrito"), Detalle=texto("detalle", True, "Señas"),
                Predeterminada=marcado("predeterminada"))


@bp.post("/direcciones")
@requiere_cliente
def direccion_crear():
    ok, direccion_id = intentar(lambda: db.ejecutar_con_salida("usp_Direccion_Crear", "DireccionId", ClienteId=_cid(),
                                                               **_datos_direccion()), "Dirección agregada.")
    # Desde el checkout se vuelve a él con la dirección nueva ya seleccionada.
    if request.form.get("volver") == "checkout":
        return redirect(url_for("tienda.checkout", direccion=direccion_id) if ok else url_for("tienda.checkout"))
    return redirect(url_for("tienda.perfil"))


@bp.post("/direcciones/<int:direccion_id>")
@requiere_cliente
def direccion_actualizar(direccion_id):
    intentar(lambda: db.ejecutar("usp_Direccion_Actualizar", DireccionId=direccion_id, ClienteId=_cid(), **_datos_direccion()),
             "Dirección actualizada.")
    return redirect(url_for("tienda.perfil"))


@bp.post("/direcciones/<int:direccion_id>/eliminar")
@requiere_cliente
def direccion_eliminar(direccion_id):
    intentar(lambda: db.ejecutar("usp_Direccion_Eliminar", DireccionId=direccion_id, ClienteId=_cid()), "Dirección eliminada.")
    return redirect(url_for("tienda.perfil"))
