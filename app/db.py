"""Acceso a datos.

REGLA DEL PROYECTO: la aplicación solo ejecuta procedimientos almacenados.
Este módulo es el único que habla con SQL Server y lo único que sabe hacer es
    EXEC dbo.usp_Algo @Param1 = ?, @Param2 = ?
Los valores SIEMPRE viajan como parámetros (?), nunca concatenados en el texto.
Los nombres del procedimiento y de los parámetros están escritos en el código
(no vienen del usuario) y además se validan con una expresión regular.
"""
import re

from flask import g

import config

try:                       # pyodbc es el driver habitual
    import pyodbc as odbc
except Exception:          # alternativa 100 % Python si pyodbc no se puede cargar
    import pypyodbc as odbc

odbc.lowercase = False     # conservar los nombres de columna tal como vienen
odbc.pooling = False

_NOMBRE_SP = re.compile(r"usp_[A-Za-z0-9_]+")
_NOMBRE_PARAM = re.compile(r"[A-Za-z][A-Za-z0-9_]*")


class ErrorBD(Exception):
    """Error devuelto por SQL Server, con un mensaje apto para mostrar al usuario."""


def _traducir(error: Exception) -> str:
    texto = str(error.args[-1]) if error.args else str(error)
    if "[SQL Server]" not in texto:
        return "No se pudo conectar con la base de datos. Verifique que SQL Server esté en ejecución."
    mensaje = texto.split("]")[-1].strip()
    mensaje = re.sub(r"\s*\(\d+\)\s*\(SQL\w+\)\s*$", "", mensaje)     # sufijo que agrega pyodbc
    # Errores de restricciones (última barrera de la base de datos) en lenguaje claro.
    if "UNIQUE KEY" in mensaje or "duplicate key" in mensaje:
        return "Ya existe un registro con ese valor (restricción de unicidad de la base de datos)."
    if "CHECK constraint" in mensaje:
        return "La base de datos rechazó el valor porque no cumple una regla de validación."
    if "REFERENCE constraint" in mensaje or "FOREIGN KEY" in mensaje:
        return "No se puede completar la operación: el registro está relacionado con otros datos."
    if "permission was denied" in mensaje:
        return "La aplicación no tiene permiso para esa operación."
    return mensaje


def conexion():
    """Una conexión por petición HTTP, guardada en flask.g."""
    if "cn" not in g:
        try:
            cn = odbc.connect(config.cadena_conexion(), autocommit=True)
        except odbc.Error as e:
            raise ErrorBD(_traducir(e)) from e
        if config.DB_EJECUTAR_COMO and config.DB_AUTENTICACION != "sql":
            # Mínimo privilegio: desde aquí la sesión solo puede ejecutar procedimientos.
            cn.cursor().execute(f"EXECUTE AS USER = '{config.DB_EJECUTAR_COMO}';")
        g.cn = cn
    return g.cn


def cerrar(_exc=None):
    cn = g.pop("cn", None)
    if cn is not None:
        try:
            cn.close()
        except Exception:
            pass


def _ejecutar(sql: str, valores: list):
    """Ejecuta y devuelve [(columnas, filas), ...], un elemento por conjunto de resultados."""
    cur = conexion().cursor()
    try:
        cur.execute(sql, valores)
        conjuntos = []
        while True:
            if cur.description:
                columnas = [c[0] for c in cur.description]
                filas = [dict(zip(columnas, fila)) for fila in cur.fetchall()]
                conjuntos.append((columnas, filas))
            if not cur.nextset():
                break
        return conjuntos
    except odbc.Error as e:
        raise ErrorBD(_traducir(e)) from e
    finally:
        cur.close()


def _armar_exec(nombre: str, params: dict, salida: str | None = None):
    if not _NOMBRE_SP.fullmatch(nombre):
        raise ValueError(f"Nombre de procedimiento no permitido: {nombre}")
    partes, valores = [], []
    for clave, valor in params.items():
        if not _NOMBRE_PARAM.fullmatch(clave):
            raise ValueError(f"Nombre de parámetro no permitido: {clave}")
        partes.append(f"@{clave} = ?")
        valores.append(valor)
    if salida:
        if not _NOMBRE_PARAM.fullmatch(salida):
            raise ValueError(f"Nombre de parámetro no permitido: {salida}")
        partes.append(f"@{salida} = @__salida OUTPUT")
    return f"EXEC dbo.{nombre} " + ", ".join(partes), valores


def consulta(nombre: str, **params):
    """Ejecuta un procedimiento de lectura. Devuelve (columnas, filas)."""
    sql, valores = _armar_exec(nombre, params)
    conjuntos = _ejecutar("SET NOCOUNT ON; " + sql + ";", valores)
    return conjuntos[0] if conjuntos else ([], [])


def filas(nombre: str, **params) -> list:
    return consulta(nombre, **params)[1]


def fila(nombre: str, **params):
    resultado = filas(nombre, **params)
    return resultado[0] if resultado else None


def ejecutar(nombre: str, **params) -> None:
    """Ejecuta un procedimiento que no devuelve filas."""
    sql, valores = _armar_exec(nombre, params)
    _ejecutar("SET NOCOUNT ON; " + sql + ";", valores)


def ejecutar_con_salida(nombre: str, salida: str, **params):
    """Ejecuta un procedimiento con un parámetro OUTPUT entero y devuelve su valor."""
    sql, valores = _armar_exec(nombre, params, salida)
    lote = f"SET NOCOUNT ON; DECLARE @__salida INT; {sql}; SELECT @__salida AS Valor;"
    conjuntos = _ejecutar(lote, valores)
    return conjuntos[-1][1][0]["Valor"] if conjuntos else None
