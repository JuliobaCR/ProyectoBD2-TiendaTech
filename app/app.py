"""TiendaTech - aplicación web (Flask) del Proyecto Programado II.

Arranque:   python app.py     ->  http://localhost:5000
Toda lectura y escritura pasa por procedimientos almacenados (ver db.py).
"""
import secrets
from decimal import Decimal

from flask import Flask, abort, render_template, request, session

import config
import db
import util
from admin import bp as admin_bp
from reportes import bp as reportes_bp
from tienda import bp as tienda_bp


def crear_app() -> Flask:
    app = Flask(__name__)
    app.config.update(SECRET_KEY=config.SECRET_KEY, SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Lax")

    app.register_blueprint(tienda_bp)
    app.register_blueprint(admin_bp, url_prefix="/admin")
    app.register_blueprint(reportes_bp, url_prefix="/admin/reportes")
    app.teardown_appcontext(db.cerrar)

    for nombre in ("dinero", "numero", "fecha_hora", "solo_fecha", "celda", "titulo_columna"):
        app.jinja_env.filters[nombre] = getattr(util, nombre)

    # --- Protección CSRF sencilla: cada formulario POST lleva un token de la sesión.
    def token_csrf() -> str:
        if "_csrf" not in session:
            session["_csrf"] = secrets.token_hex(16)
        return session["_csrf"]

    @app.before_request
    def verificar_csrf():
        if request.method == "POST" and request.form.get("_csrf") != session.get("_csrf"):
            abort(400, "Formulario vencido. Vuelva a cargar la página e intente de nuevo.")

    @app.context_processor
    def variables_globales():
        carrito_unidades = 0
        if session.get("rol") == util.ROL_CLIENTE:
            try:
                resumen = db.fila("usp_Carrito_Resumen", ClienteId=session["cid"])
                carrito_unidades = int(resumen["Unidades"]) if resumen else 0
            except db.ErrorBD:
                pass
        return dict(csrf=token_csrf, carrito_unidades=carrito_unidades,
                    es_admin=session.get("rol") == util.ROL_ADMIN,
                    es_cliente=session.get("rol") == util.ROL_CLIENTE,
                    es_decimal=lambda v: isinstance(v, Decimal))

    @app.errorhandler(db.ErrorBD)
    def error_bd(e):
        return render_template("error.html", titulo="No se pudo completar la operación", mensaje=str(e)), 500

    @app.errorhandler(400)
    def error_400(e):
        return render_template("error.html", titulo="Solicitud no válida", mensaje=e.description), 400

    @app.errorhandler(404)
    def error_404(_e):
        return render_template("error.html", titulo="No encontrado", mensaje="La página o el registro que busca no existe."), 404

    return app


app = crear_app()

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=config.PUERTO, debug=False)
