@echo off
rem ====================================================================
rem  Arranca la aplicacion TiendaTech y abre el navegador.
rem  Doble clic en este archivo. Para detenerla, cierre esta ventana.
rem  La primera vez crea el entorno de Python e instala las dependencias.
rem ====================================================================
setlocal
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo Creando el entorno de Python...
    python -m venv .venv || goto :error
    ".venv\Scripts\python.exe" -m pip install --quiet -r app\requirements.txt
)

echo.
echo TiendaTech en http://localhost:5000
echo   Administrador: admin@tiendatech.test
echo   Cliente:       cliente01@correo.test
echo   (las contrasenas de demostracion estan en el README)
echo.
echo Para detener la aplicacion cierre esta ventana.
start "" "http://localhost:5000"
".venv\Scripts\python.exe" app\app.py
exit /b 0

:error
echo No se pudo crear el entorno. Verifique que Python este instalado.
pause
exit /b 1
