"""PRUEBA 10: dos compras simultáneas con stock limitado, sin sobreventa.

Deja UNA sola unidad de un producto y lanza dos compradores al mismo tiempo
(dos hilos, cada uno con su propia conexión a SQL Server, sincronizados con una
barrera para que ejecuten usp_Pedido_Confirmar en el mismo instante).

Resultado esperado: exactamente una compra se confirma y la otra recibe el error
"Existencia insuficiente"; la existencia termina en 0 (nunca negativa) y existe
un único pedido con ese producto.

Uso (desde la raíz del proyecto):
    .venv\\Scripts\\python pruebas\\prueba_concurrencia.py

La prueba restaura todo al final: cancela el pedido ganador (reintegra la unidad)
y repone las unidades que retiró.
"""
import sys
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))

from flask import Flask  # noqa: E402

import db  # noqa: E402

PRODUCTO = 55                      # ACC-007 Sony control DualSense
ADMIN = 1
COMPRADORES = [(19, 19), (20, 20)]  # (ClienteId, DireccionId)
app = Flask(__name__)


def existencia() -> int:
    return db.fila("usp_Producto_Obtener", ProductoId=PRODUCTO)["Existencia"]


def comprar(cliente: int, direccion: int, barrera: threading.Barrier, resultados: dict) -> None:
    with app.app_context():           # cada hilo abre su propia conexión
        try:
            db.conexion()
            barrera.wait(timeout=10)  # los dos hilos salen a la vez
            pedido = db.ejecutar_con_salida("usp_Pedido_Confirmar", "PedidoId",
                                            ClienteId=cliente, DireccionId=direccion, MetodoPagoId=1)
            resultados[cliente] = ("CONFIRMADO", pedido)
        except db.ErrorBD as e:
            resultados[cliente] = ("RECHAZADO", str(e))
        finally:
            db.cerrar()


def main() -> int:
    with app.app_context():
        inicial = existencia()
        retiradas = inicial - 1
        if retiradas > 0:
            db.ejecutar_con_salida("usp_Inventario_RegistrarMovimiento", "MovimientoId", ProductoId=PRODUCTO, Tipo="SALIDA",
                                   Cantidad=retiradas, UsuarioId=ADMIN, Motivo="Prueba 10: dejar una sola unidad")
        for cliente, _ in COMPRADORES:
            db.ejecutar("usp_Carrito_Vaciar", ClienteId=cliente)
            db.ejecutar("usp_Carrito_Agregar", ClienteId=cliente, ProductoId=PRODUCTO, Cantidad=1)
        print(f"Datos iniciales: existencia = {existencia()} unidad; dos clientes la tienen en su carrito.")
        db.cerrar()

    resultados: dict = {}
    barrera = threading.Barrier(len(COMPRADORES))
    hilos = [threading.Thread(target=comprar, args=(c, d, barrera, resultados)) for c, d in COMPRADORES]
    for h in hilos:
        h.start()
    for h in hilos:
        h.join()

    for cliente, (estado, detalle) in sorted(resultados.items()):
        print(f"  Cliente {cliente}: {estado} -> {detalle}")

    with app.app_context():
        final = existencia()
        confirmados = [(c, d) for c, (e, d) in resultados.items() if e == "CONFIRMADO"]
        rechazados = [d for _, (e, d) in resultados.items() if e == "RECHAZADO"]
        correcto = (len(confirmados) == 1 and len(rechazados) == 1
                    and "Existencia insuficiente" in rechazados[0] and final == 0)
        print(f"Existencia final = {final} (esperado 0, nunca negativa)")
        print(f"Pedidos confirmados = {len(confirmados)} (esperado 1); rechazados = {len(rechazados)} (esperado 1)")
        print("RESULTADO:", "PASA - no hubo sobreventa" if correcto else "FALLA")

        # Restaurar los datos: cancelar el pedido ganador y reponer lo retirado.
        for _cliente, pedido in confirmados:
            db.ejecutar("usp_Pedido_Cancelar", PedidoId=pedido, UsuarioId=ADMIN, Motivo="Prueba 10: restaurar datos")
        if retiradas > 0:
            db.ejecutar_con_salida("usp_Inventario_RegistrarMovimiento", "MovimientoId", ProductoId=PRODUCTO, Tipo="ENTRADA",
                                   Cantidad=retiradas, UsuarioId=ADMIN, Motivo="Prueba 10: reponer unidades")
        for cliente, _ in COMPRADORES:
            db.ejecutar("usp_Carrito_Vaciar", ClienteId=cliente)
        print(f"Datos restaurados: existencia = {existencia()} (inicial {inicial}).")
        db.cerrar()
    return 0 if correcto else 1


if __name__ == "__main__":
    sys.exit(main())
