/* =====================================================================
   08_seguridad.sql  -  Principio de mínimo privilegio
   La aplicación NO se conecta como administrador de la base. Opera con el
   usuario de base de datos "app_tiendatech", que:
     - pertenece al rol rol_aplicacion,
     - solo tiene permiso EXECUTE sobre los procedimientos del esquema dbo,
     - NO puede hacer SELECT/INSERT/UPDATE/DELETE directo sobre ninguna tabla
       (los procedimientos sí pueden, por encadenamiento de propiedad).

   Dos formas de usarlo (ver README y app/config.example.env):
     A) Autenticación de Windows (instalación por defecto de SQL Express):
        la aplicación abre la conexión y de inmediato ejecuta
        EXECUTE AS USER = 'app_tiendatech', con lo que el resto de la sesión
        queda limitada a los permisos del rol.
     B) Autenticación de SQL Server (modo mixto): crear un inicio de sesión
        propio y asociarlo al usuario. La contraseña NO va en este script:
          CREATE LOGIN app_tiendatech_login WITH PASSWORD = '<definir>';
          ALTER USER app_tiendatech WITH LOGIN = app_tiendatech_login;
   ===================================================================== */
SET NOCOUNT ON;
GO
USE TiendaTechDB;
GO
IF DATABASE_PRINCIPAL_ID(N'rol_aplicacion') IS NULL
    CREATE ROLE rol_aplicacion;
GO
IF DATABASE_PRINCIPAL_ID(N'app_tiendatech') IS NULL
    CREATE USER app_tiendatech WITHOUT LOGIN;
GO
ALTER ROLE rol_aplicacion ADD MEMBER app_tiendatech;
GO
/* Único permiso: ejecutar procedimientos. Nada sobre tablas ni vistas. */
GRANT EXECUTE ON SCHEMA::dbo TO rol_aplicacion;
GO
PRINT '08_seguridad.sql: rol y usuario de aplicación configurados.';
GO
