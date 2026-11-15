"""Configuración de la aplicación.

Los valores salen de variables de entorno o del archivo app/.env (que NO se sube
a Git). Ver app/config.example.env. Aquí no hay contraseñas ni secretos.
"""
import os
import re
import secrets
from pathlib import Path

_RAIZ = Path(__file__).resolve().parent


def _cargar_env(ruta: Path) -> None:
    """Lee un archivo CLAVE=valor sencillo y lo pasa a variables de entorno."""
    if not ruta.exists():
        return
    for linea in ruta.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if not linea or linea.startswith("#") or "=" not in linea:
            continue
        clave, valor = linea.split("=", 1)
        os.environ.setdefault(clave.strip(), valor.strip())


_cargar_env(_RAIZ / ".env")

DB_SERVIDOR = os.environ.get("DB_SERVIDOR", r"localhost\SQLEXPRESS")
DB_NOMBRE = os.environ.get("DB_NOMBRE", "TiendaTechDB")
DB_DRIVER = os.environ.get("DB_DRIVER", "ODBC Driver 18 for SQL Server")
# Autenticación: "windows" (por defecto) o "sql".
DB_AUTENTICACION = os.environ.get("DB_AUTENTICACION", "windows").lower()
DB_USUARIO = os.environ.get("DB_USUARIO", "")
DB_CONTRASENA = os.environ.get("DB_CONTRASENA", "")
# Con autenticación de Windows la sesión se limita a este usuario de base de datos
# (solo puede ejecutar procedimientos). Dejar vacío si DB_USUARIO ya es el usuario limitado.
DB_EJECUTAR_COMO = os.environ.get("DB_EJECUTAR_COMO", "app_tiendatech")
if DB_EJECUTAR_COMO and not re.fullmatch(r"[A-Za-z0-9_]+", DB_EJECUTAR_COMO):
    raise ValueError("DB_EJECUTAR_COMO solo admite letras, números y guion bajo.")

# Clave de las cookies de sesión. Si no se define, se genera una al arrancar.
SECRET_KEY = os.environ.get("SECRET_KEY") or secrets.token_hex(32)
PUERTO = int(os.environ.get("PUERTO", "5000"))


def cadena_conexion() -> str:
    partes = [
        f"DRIVER={{{DB_DRIVER}}}",
        f"SERVER={DB_SERVIDOR}",
        f"DATABASE={DB_NOMBRE}",
        "TrustServerCertificate=yes",
        "APP=TiendaTech",
    ]
    if DB_AUTENTICACION == "sql":
        partes += [f"UID={DB_USUARIO}", f"PWD={DB_CONTRASENA}"]
    else:
        partes.append("Trusted_Connection=yes")
    return ";".join(partes) + ";"
