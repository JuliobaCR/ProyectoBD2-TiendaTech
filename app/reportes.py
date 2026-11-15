"""Panel de reportes R1-R10. Cada reporte es un procedimiento almacenado; aquí solo se
describe qué parámetros pide, se muestra el resultado y se exporta a CSV."""
import csv
import datetime as dt
import io

from flask import Blueprint, Response, abort, flash, render_template, request

import db
from util import ErrorEntrada, celda, entero, fecha, requiere_admin, texto

bp = Blueprint("reportes", __name__)

ANIO = dt.date.today().year

# Tipos de parámetro: fecha, anio, entero, opcion(lista de valores), estado
REPORTES = {
    "r1": dict(titulo="R1 · Top clientes", sp="usp_Reporte_R1_TopClientes",
               nota="Monto comprado, cantidad de pedidos y productos diferentes. Usa HAVING para exigir un mínimo de pedidos.",
               params=[("Desde", "fecha", "Desde", None), ("Hasta", "fecha", "Hasta", None),
                       ("Top", "entero", "Cantidad de clientes", 5), ("MinPedidos", "entero", "Mínimo de pedidos", 1)],
               grafico=("Cliente", "MontoComprado")),
    "r2": dict(titulo="R2 · Matriz cliente × categoría", sp="usp_Reporte_R2_MatrizClienteCategoria",
               nota="Total comprado por cada cliente en cada categoría (PIVOT).",
               params=[("Desde", "fecha", "Desde", None), ("Hasta", "fecha", "Hasta", None)], grafico=None),
    "r3": dict(titulo="R3 · Ventas mensuales por marca", sp="usp_Reporte_R3_VentasMensualesPorMarca",
               nota="Matriz marca × mes con agregación condicional; los meses sin ventas aparecen en 0.",
               params=[("Anio", "anio", "Año", ANIO)], grafico=("Marca", "Total")),
    "r4": dict(titulo="R4 · Evolución mensual", sp="usp_Reporte_R4_EvolucionMensual",
               nota="Ventas, cantidad de pedidos y ticket promedio por mes.",
               params=[("Anio", "anio", "Año", ANIO)], grafico=("NombreMes", "Ventas")),
    "r5": dict(titulo="R5 · Productos más vendidos", sp="usp_Reporte_R5_ProductosMasVendidos",
               nota="Top por unidades o por ingresos, con categoría y marca (RANK).",
               params=[("Desde", "fecha", "Desde", None), ("Hasta", "fecha", "Hasta", None),
                       ("Criterio", [("U", "Unidades"), ("I", "Ingresos")], "Ordenar por", "U"), ("Top", "entero", "Cantidad", 10)],
               grafico=("Producto", "Unidades")),
    "r6": dict(titulo="R6 · Inventario crítico", sp="usp_Reporte_R6_InventarioCritico",
               nota="Productos bajo mínimo, faltantes y estimación de reposición.",
               params=[("DiasAnalisis", "entero", "Días de ventas a analizar", 90)], grafico=None),
    "r7": dict(titulo="R7 · Rentabilidad", sp="usp_Reporte_R7_Rentabilidad",
               nota="Ingresos, costo histórico y utilidad bruta. La utilidad no es lo mismo que las ventas.",
               params=[("AgruparPor", [("C", "Categoría"), ("P", "Producto")], "Agrupar por", "C"),
                       ("Desde", "fecha", "Desde", None), ("Hasta", "fecha", "Hasta", None)],
               grafico=("0", "UtilidadBruta")),
    "r8": dict(titulo="R8 · Clientes sin compras", sp="usp_Reporte_R8_ClientesSinCompras",
               nota="Clientes que nunca han comprado o que no compraron en el rango (NOT EXISTS). Sin fechas: nunca han comprado.",
               params=[("Desde", "fecha", "Desde", None), ("Hasta", "fecha", "Hasta", None)], grafico=None),
    "r9": dict(titulo="R9 · Comparación temporal", sp="usp_Reporte_R9_ComparacionMensual",
               nota="Ventas de cada mes y variación absoluta y porcentual contra el mes anterior (LAG).",
               params=[("Anio", "anio", "Año", ANIO)], grafico=("NombreMes", "VariacionAbsoluta")),
    "r10": dict(titulo="R10 · Resumen de pedidos", sp="usp_Reporte_R10_ResumenPedidos",
                nota="Pedidos con estado, número de líneas, total, fecha y cliente.",
                params=[("EstadoId", "estado", "Estado", None), ("Desde", "fecha", "Desde", None),
                        ("Hasta", "fecha", "Hasta", None), ("Buscar", "texto", "Cliente o correo", None)], grafico=None),
}


def _leer_parametros(cfg):
    """Convierte los valores del formulario en parámetros tipados del procedimiento."""
    valores, mostrados = {}, {}
    for nombre, tipo, etiqueta, defecto in cfg["params"]:
        presente = nombre in request.args
        if tipo == "fecha":
            valor = fecha(nombre, etiqueta=etiqueta)
        elif tipo in ("entero", "anio", "estado"):
            valor = entero(nombre, etiqueta=etiqueta)
            if valor is None and not presente:
                valor = defecto
        elif tipo == "texto":
            valor = texto(nombre)
        else:   # lista de opciones
            valor = request.args.get(nombre) or defecto
            if valor not in [codigo for codigo, _ in tipo]:
                valor = defecto
        mostrados[nombre] = valor
        if valor is not None:
            valores[nombre] = valor
    return valores, mostrados


def _ejecutar(rid):
    cfg = REPORTES.get(rid)
    if not cfg:
        abort(404)
    valores, mostrados = _leer_parametros(cfg)
    columnas, filas = db.consulta(cfg["sp"], **valores)
    return cfg, mostrados, columnas, filas


@bp.get("/")
@requiere_admin
def indice():
    return render_template("admin/reportes.html", reportes=REPORTES)


@bp.get("/<rid>")
@requiere_admin
def ver(rid):
    try:
        cfg, mostrados, columnas, filas = _ejecutar(rid)
    except (ErrorEntrada, db.ErrorBD) as e:
        flash(str(e), "error")
        cfg, mostrados, columnas, filas = REPORTES.get(rid) or abort(404), {}, [], []

    grafico = None
    if cfg["grafico"] and filas:
        col_etiqueta, col_valor = cfg["grafico"]
        if col_etiqueta == "0":
            col_etiqueta = columnas[1] if columnas[0] == "SKU" else columnas[0]
        puntos = [(str(f[col_etiqueta]), float(f[col_valor] or 0)) for f in filas][:15]
        maximo = max((abs(v) for _, v in puntos), default=0) or 1
        grafico = dict(titulo=col_valor, puntos=[(e, v, round(abs(v) * 100 / maximo, 1)) for e, v in puntos])

    return render_template("admin/reporte.html", rid=rid, cfg=cfg, valores=mostrados, columnas=columnas, filas=filas,
                           grafico=grafico, estados=db.filas("usp_EstadoPedido_Listar"), reportes=REPORTES,
                           consulta=request.query_string.decode())


@bp.get("/<rid>.csv")
@requiere_admin
def exportar(rid):
    """Exporta el mismo resultado que se ve en pantalla. El BOM hace que Excel lea bien las tildes."""
    cfg, _mostrados, columnas, filas = _ejecutar(rid)
    salida = io.StringIO()
    escritor = csv.writer(salida, delimiter=";", lineterminator="\r\n")
    escritor.writerow(columnas)
    for f in filas:
        escritor.writerow(["" if f[c] is None else (str(f[c]).replace(".", ",") if hasattr(f[c], "as_tuple") else celda(f[c]))
                           for c in columnas])
    nombre = f"{rid}_{dt.date.today():%Y%m%d}.csv"
    return Response("﻿" + salida.getvalue(), mimetype="text/csv; charset=utf-8",
                    headers={"Content-Disposition": f'attachment; filename="{nombre}"'})
