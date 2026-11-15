"""Genera una ilustración SVG por producto en app/static/img/productos/<SKU>.svg.

Son imágenes propias (el aparato dibujado con formas simples sobre un fondo suave
del color de su categoría), así el proyecto no depende de internet ni usa fotos
con derechos de autor. Si se quiere usar fotos reales, basta con poner la URL en
el campo "Imagen" del producto.

Uso (desde la raíz del proyecto, con la base ya creada):
    .venv\\Scripts\\python herramientas\\generar_imagenes.py
"""
import html
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "app"))

from flask import Flask  # noqa: E402

import db  # noqa: E402

TINTA = "#111827"


def _pantalla(x, y, w, h, r):
    """Pantalla con el degradado de la categoría y un reflejo diagonal."""
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="url(#p)"/>'
            f'<path d="M{x} {y + h}L{x + w * .55} {y}H{x + w * .8}L{x + w * .25} {y + h}z" fill="#fff" opacity=".09"/>')


def _laptop():
    return (f'<rect x="138" y="84" width="204" height="134" rx="10" fill="{TINTA}"/>' + _pantalla(146, 92, 188, 118, 5)
            + '<path d="M104 222h272l-12 16a10 10 0 0 1-8 4H124a10 10 0 0 1-8-4z" fill="#cbd5e1"/>'
              '<rect x="214" y="222" width="52" height="6" rx="3" fill="#94a3b8"/>')


def _celular():
    return (f'<rect x="194" y="56" width="92" height="196" rx="18" fill="{TINTA}"/>' + _pantalla(200, 62, 80, 184, 13)
            + f'<rect x="226" y="68" width="28" height="7" rx="3.5" fill="{TINTA}"/>')


def _tablet():
    return (f'<rect x="160" y="62" width="160" height="204" rx="16" fill="{TINTA}"/>' + _pantalla(168, 70, 144, 188, 9)
            + '<circle cx="240" cy="66" r="1.8" fill="#475569"/>')


def _monitor():
    return (f'<rect x="112" y="72" width="256" height="152" rx="10" fill="{TINTA}"/>' + _pantalla(120, 80, 240, 128, 5)
            + '<path d="M226 224h28l4 28h-36z" fill="#94a3b8"/><rect x="184" y="250" width="112" height="9" rx="4.5" fill="#cbd5e1"/>')


def _teclado():
    resaltadas = {(0, 12), (1, 0), (2, 12)}
    teclas = "".join(
        f'<rect x="{112 + c * 19.5 + (f % 2) * 4:.1f}" y="{150 + f * 21}" width="15" height="15" rx="3.5" '
        f'fill="{"url(#p)" if (f, c) in resaltadas else "#374151"}"/>'
        for f in range(3) for c in range(13))
    return (f'<rect x="98" y="136" width="284" height="104" rx="14" fill="{TINTA}"/>' + teclas
            + '<rect x="112" y="213" width="38" height="15" rx="3.5" fill="#374151"/>'
              '<rect x="156" y="213" width="150" height="15" rx="3.5" fill="#4b5563"/>'
              '<rect x="312" y="213" width="56" height="15" rx="3.5" fill="#374151"/>')


def _mouse():
    return (f'<rect x="192" y="78" width="96" height="172" rx="48" fill="{TINTA}"/>'
            '<path d="M240 78v62M192 140h96" stroke="#374151" stroke-width="3"/>'
            '<rect x="233" y="100" width="14" height="30" rx="7" fill="url(#p)"/>')


def _audio():
    return (f'<path d="M158 178v-34a82 82 0 0 1 164 0v34" fill="none" stroke="{TINTA}" stroke-width="16" stroke-linecap="round"/>'
            f'<rect x="136" y="160" width="46" height="84" rx="20" fill="{TINTA}"/>'
            f'<rect x="298" y="160" width="46" height="84" rx="20" fill="{TINTA}"/>'
            '<rect x="146" y="176" width="12" height="52" rx="6" fill="url(#p)"/>'
            '<rect x="322" y="176" width="12" height="52" rx="6" fill="url(#p)"/>')


def _almacenamiento():
    pines = "".join(f'<rect x="{168 + i * 13}" y="232" width="8" height="14" rx="1.5" fill="#eab308"/>' for i in range(11))
    return (f'<rect x="132" y="104" width="216" height="134" rx="14" fill="{TINTA}"/>'
            '<rect x="150" y="122" width="180" height="62" rx="8" fill="url(#p)"/>'
            '<rect x="164" y="138" width="86" height="8" rx="4" fill="#fff" opacity=".85"/>'
            '<rect x="164" y="154" width="54" height="8" rx="4" fill="#fff" opacity=".5"/>'
            '<circle cx="316" cy="210" r="6" fill="#374151"/><circle cx="164" cy="210" r="6" fill="#374151"/>' + pines)


def _reloj():
    return ('<rect x="210" y="40" width="60" height="240" rx="14" fill="#374151"/>'
            f'<rect x="178" y="100" width="124" height="124" rx="30" fill="{TINTA}"/>' + _pantalla(188, 110, 104, 104, 22)
            + '<rect x="302" y="146" width="7" height="24" rx="3.5" fill="#374151"/>'
              '<path d="M240 132v32l20 12" fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round" stroke-linejoin="round" opacity=".92"/>')


def _accesorio():
    return ('<rect x="216" y="72" width="12" height="34" rx="3" fill="#94a3b8"/><rect x="252" y="72" width="12" height="34" rx="3" fill="#94a3b8"/>'
            f'<rect x="176" y="100" width="128" height="128" rx="28" fill="{TINTA}"/>'
            '<path d="M250 124l-34 46h24l-10 34 36-48h-24z" fill="url(#p)"/>'
            '<path d="M240 228v20a18 18 0 0 0 18 18h44" fill="none" stroke="#64748b" stroke-width="7" stroke-linecap="round"/>')


# Por prefijo de SKU: (fondo claro 1, fondo claro 2, acento 1, acento 2, función que dibuja el aparato).
ESTILOS = {
    "LAP": ("#eef3ff", "#dbe6ff", "#60a5fa", "#2563eb", _laptop),
    "CEL": ("#f5f0ff", "#e7dcff", "#c084fc", "#7c3aed", _celular),
    "TAB": ("#e9fbf6", "#d2f3ea", "#5eead4", "#0d9488", _tablet),
    "MON": ("#eef2f6", "#dde4ec", "#7dd3fc", "#0369a1", _monitor),
    "TEC": ("#fff3ea", "#ffe3cf", "#fdba74", "#ea580c", _teclado),
    "MOU": ("#e8f8fd", "#d0eef8", "#67e8f9", "#0891b2", _mouse),
    "AUD": ("#fdeff8", "#fadcf0", "#f9a8d4", "#db2777", _audio),
    "ALM": ("#f0f9e8", "#e0f1d1", "#bef264", "#65a30d", _almacenamiento),
    "REL": ("#fff7e6", "#ffeccc", "#fcd34d", "#d97706", _reloj),
    "ACC": ("#f1f3f7", "#e2e6ee", "#a5b4fc", "#4f46e5", _accesorio),
}


def svg(sku: str, nombre: str, marca: str) -> str:
    claro1, claro2, acento1, acento2, dibujar = ESTILOS.get(sku[:3], ESTILOS["ACC"])
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 480 360" font-family="Segoe UI, Arial, sans-serif" '
        f'role="img" aria-label="{html.escape(nombre)}">'
        f'<defs><linearGradient id="f" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{claro1}"/><stop offset="1" stop-color="{claro2}"/></linearGradient>'
        f'<linearGradient id="p" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{acento1}"/><stop offset="1" stop-color="{acento2}"/></linearGradient>'
        '<radialGradient id="h" cx=".5" cy=".42" r=".55"><stop offset="0" stop-color="#fff" stop-opacity=".95"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient></defs>'
        '<rect width="480" height="360" fill="url(#f)"/><rect width="480" height="360" fill="url(#h)"/>'
        f'<circle cx="426" cy="42" r="96" fill="{acento2}" opacity=".07"/><circle cx="44" cy="330" r="74" fill="{acento2}" opacity=".06"/>'
        f'<ellipse cx="240" cy="292" rx="132" ry="13" fill="{TINTA}" opacity=".13"/>'
        f'{dibujar()}'
        f'<text x="26" y="40" font-size="13" font-weight="700" fill="{TINTA}" fill-opacity=".5" letter-spacing="2.2">{html.escape(marca.upper())}</text>'
        '</svg>')


SIN_IMAGEN = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 480 360" font-family="Segoe UI, Arial, sans-serif">'
    '<rect width="480" height="360" fill="#eef1f5"/>'
    '<rect x="190" y="112" width="100" height="80" rx="12" fill="none" stroke="#98a2b3" stroke-width="6"/>'
    '<circle cx="218" cy="138" r="8" fill="#98a2b3"/><path d="M196 184l30-30 20 18 16-14 22 26z" fill="#98a2b3"/>'
    '<text x="240" y="232" text-anchor="middle" font-size="15" font-weight="600" fill="#667085">Sin imagen</text></svg>')


def main() -> None:
    destino = RAIZ / "app" / "static" / "img" / "productos"
    destino.mkdir(parents=True, exist_ok=True)
    app = Flask(__name__)
    with app.app_context():
        productos = db.filas("usp_Producto_ListarAdmin")
        for p in productos:
            (destino / f"{p['SKU']}.svg").write_text(svg(p["SKU"], p["Nombre"], p["Marca"]), encoding="utf-8")
        db.cerrar()
    (destino.parent / "sin-imagen.svg").write_text(SIN_IMAGEN, encoding="utf-8")
    print(f"{len(productos)} imágenes generadas en {destino}")


if __name__ == "__main__":
    main()
