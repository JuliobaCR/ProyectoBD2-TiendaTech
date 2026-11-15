"""Utilidades compartidas: control de acceso por rol, lectura de formularios y formato."""
import datetime as dt
from decimal import Decimal, InvalidOperation
from functools import wraps

from flask import flash, redirect, request, session, url_for

import db

ROL_ADMIN, ROL_CLIENTE = 1, 2


class ErrorEntrada(Exception):
    """Dato mal escrito en un formulario (validación visible en la interfaz)."""


# ---------------------------------------------------------------- acceso por rol
def requiere_sesion(vista):
    @wraps(vista)
    def envoltura(*args, **kwargs):
        if "uid" not in session:
            flash("Inicie sesión para continuar.", "aviso")
            return redirect(url_for("tienda.login", siguiente=request.path))
        return vista(*args, **kwargs)
    return envoltura


def requiere_cliente(vista):
    @wraps(vista)
    def envoltura(*args, **kwargs):
        if "uid" not in session:
            flash("Inicie sesión para continuar.", "aviso")
            return redirect(url_for("tienda.login", siguiente=request.path))
        if session.get("rol") != ROL_CLIENTE:
            flash("Esa sección es solo para clientes.", "error")
            return redirect(url_for("admin.panel"))
        return vista(*args, **kwargs)
    return envoltura


def requiere_admin(vista):
    @wraps(vista)
    def envoltura(*args, **kwargs):
        if "uid" not in session:
            flash("Inicie sesión como administrador.", "aviso")
            return redirect(url_for("tienda.login", siguiente=request.path))
        if session.get("rol") != ROL_ADMIN:
            flash("No tiene permiso para entrar a la administración.", "error")
            return redirect(url_for("tienda.catalogo"))
        return vista(*args, **kwargs)
    return envoltura


# ---------------------------------------------------------------- formularios
def _origen():
    return request.form if request.method == "POST" else request.args


def texto(nombre, obligatorio=False, etiqueta=None):
    valor = (_origen().get(nombre) or "").strip()
    if obligatorio and not valor:
        raise ErrorEntrada(f"El campo «{etiqueta or nombre}» es obligatorio.")
    return valor or None


def entero(nombre, obligatorio=False, etiqueta=None):
    crudo = (_origen().get(nombre) or "").strip()
    if not crudo:
        if obligatorio:
            raise ErrorEntrada(f"El campo «{etiqueta or nombre}» es obligatorio.")
        return None
    try:
        return int(crudo)
    except ValueError:
        raise ErrorEntrada(f"«{etiqueta or nombre}» debe ser un número entero.") from None


def decimal(nombre, obligatorio=False, etiqueta=None):
    crudo = (_origen().get(nombre) or "").strip().replace(" ", "").replace(",", ".")
    if not crudo:
        if obligatorio:
            raise ErrorEntrada(f"El campo «{etiqueta or nombre}» es obligatorio.")
        return None
    try:
        return Decimal(crudo)
    except InvalidOperation:
        raise ErrorEntrada(f"«{etiqueta or nombre}» debe ser un número.") from None


def fecha(nombre, obligatorio=False, etiqueta=None):
    crudo = (_origen().get(nombre) or "").strip()
    if not crudo:
        if obligatorio:
            raise ErrorEntrada(f"El campo «{etiqueta or nombre}» es obligatorio.")
        return None
    try:
        return dt.date.fromisoformat(crudo)
    except ValueError:
        raise ErrorEntrada(f"«{etiqueta or nombre}» no es una fecha válida.") from None


def marcado(nombre) -> int:
    return 1 if _origen().get(nombre) in ("1", "on", "true") else 0


def intentar(accion, exito=None):
    """Ejecuta una acción; si SQL Server o el formulario la rechazan, muestra el mensaje.

    Devuelve (True, resultado) o (False, None).
    """
    try:
        resultado = accion()
    except (db.ErrorBD, ErrorEntrada) as e:
        flash(str(e), "error")
        return False, None
    if exito:
        flash(exito(resultado) if callable(exito) else exito, "ok")
    return True, resultado


# ---------------------------------------------------------------- formato
def dinero(valor) -> str:
    if valor is None:
        return "—"
    valor = Decimal(valor)
    patron = "{:,.0f}" if valor == valor.to_integral_value() else "{:,.2f}"
    return "₡" + patron.format(valor).replace(",", " ").replace(".", ",")


def numero(valor) -> str:
    if valor is None:
        return "—"
    if isinstance(valor, Decimal):
        patron = "{:,.0f}" if valor == valor.to_integral_value() else "{:,.2f}"
        return patron.format(valor).replace(",", " ").replace(".", ",")
    return str(valor)


def fecha_hora(valor) -> str:
    if valor is None:
        return "—"
    if isinstance(valor, dt.datetime):
        return valor.strftime("%d/%m/%Y %H:%M")
    if isinstance(valor, dt.date):
        return valor.strftime("%d/%m/%Y")
    return str(valor)


def solo_fecha(valor) -> str:
    if valor is None:
        return "—"
    return valor.strftime("%d/%m/%Y") if hasattr(valor, "strftime") else str(valor)


def titulo_columna(nombre) -> str:
    """'TicketPromedio' -> 'Ticket promedio' (encabezados de las tablas de reportes)."""
    import re
    partes = re.sub(r"(?<=[a-záéíóúñ])(?=[A-Z])", " ", str(nombre)).split(" ")
    return " ".join([partes[0]] + [p.lower() for p in partes[1:]])


def celda(valor) -> str:
    """Formato genérico para las tablas de reportes."""
    if valor is None:
        return "—"
    if isinstance(valor, bool):
        return "Sí" if valor else "No"
    if isinstance(valor, Decimal):
        return numero(valor)
    if isinstance(valor, (dt.datetime, dt.date)):
        return fecha_hora(valor)
    return str(valor)
