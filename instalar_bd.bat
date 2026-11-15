@echo off
rem ====================================================================
rem  Crea TiendaTechDB desde cero ejecutando los scripts en orden.
rem  Uso:   instalar_bd.bat                 (usa localhost\SQLEXPRESS)
rem         instalar_bd.bat MI_SERVIDOR\INSTANCIA
rem  Requiere sqlcmd y autenticacion de Windows con permiso para crear bases.
rem  ATENCION: si TiendaTechDB ya existe, se elimina y se vuelve a crear.
rem ====================================================================
setlocal
set "SERVIDOR=%~1"
if "%SERVIDOR%"=="" set "SERVIDOR=localhost\SQLEXPRESS"

for %%F in (01_esquema 02_datos 03_procedimientos 04_vistas 05_triggers 06_reportes 08_seguridad) do (
    echo.
    echo === sql\%%F.sql ===
    sqlcmd -S "%SERVIDOR%" -E -C -b -l 60 -f 65001 -i "%~dp0sql\%%F.sql"
    if errorlevel 1 goto :error
)
echo.
echo Base de datos TiendaTechDB instalada correctamente en %SERVIDOR%.
echo Para ejecutar las pruebas:  sqlcmd -S "%SERVIDOR%" -E -C -f 65001 -W -i sql\07_pruebas.sql
exit /b 0

:error
echo.
echo ERROR: la instalacion se detuvo en el script anterior. Revise el mensaje.
exit /b 1
