# -*- coding: utf-8 -*-
"""
Extrae campanas e interacciones_marketing de MongoDB (los perfiles los extrae Extraer_Perfiles_Mongo.py) (marketing_bi) y las deja SIN transformar
en el esquema stg del Data Warehouse (SQL Server). Las transformaciones
T10-T19 se hacen despues, en SQL.

Uso (desde la carpeta BI_GrupoN, lo llama 00_Ejecutar_Todo.ps1):
    python extraccion_mongo/Extraer_Mongo.py --grupo 4
Opciones (o variables de entorno):
    --mongo-uri   MONGO_URI    por defecto mongodb://localhost:27017
    --mongo-db    MONGO_DB     por defecto marketing_bi
    --server      SQL_SERVER   por defecto localhost\\SQLEXPRESS
    --grupo       numero del grupo -> base FINALBI_DW_Grupo<N>
NO se escriben claves en el codigo: si usan Atlas, pasen la URI por
--mongo-uri o por la variable MONGO_URI.

QUE SE HACE COMO GUIA
1. Se conecta a MongoDB con pymongo.
2. Se conecta a SQL Server con pyodbc.
3. Crea sus tablas de staging: stg.mongo_campanas y stg.mongo_interacciones.
4. Lee los documentos de Mongo y los inserta en esas tablas, sin limpiar (fechas en texto, presupuesto como “11.700.000”, eventos como JSON).
5. Anota en stg.ControlExtraccion cuántos documentos había y cuántos se cargaron.
"""
import argparse, json, os, sys
from datetime import datetime, timezone

import pymongo
import pyodbc


def args():
    a = argparse.ArgumentParser()
    a.add_argument("--grupo", required=True, help="numero del grupo, p. ej. 4")
    a.add_argument("--mongo-uri", default=os.getenv("MONGO_URI", "mongodb://localhost:27017"))
    a.add_argument("--mongo-db", default=os.getenv("MONGO_DB", "marketing_bi"))
    a.add_argument("--server", default=os.getenv("SQL_SERVER", r"localhost\SQLEXPRESS"))
    return a.parse_args()


def conectar_sql(server, base):
    # Usa el driver ODBC mas nuevo que haya instalado
    drivers = [d for d in pyodbc.drivers() if "SQL Server" in d]
    pref = [d for d in drivers if "ODBC Driver 18" in d] + [d for d in drivers if "ODBC Driver 17" in d] + drivers
    if not pref:
        sys.exit("No hay driver ODBC para SQL Server instalado.")
    cs = (f"DRIVER={{{pref[0]}}};SERVER={server};DATABASE={base};"
          "Trusted_Connection=yes;TrustServerCertificate=yes;")
    return pyodbc.connect(cs)


def f_iso(v):
    """datetime de Mongo (UTC) -> 'yyyy-mm-ddThh:mi:ss'. Si ya es texto (dd/mm/aaaa hh:mm) se deja igual."""
    if v is None:
        return None
    if isinstance(v, datetime):
        if v.tzinfo is not None:
            v = v.astimezone(timezone.utc).replace(tzinfo=None)
        return v.strftime("%Y-%m-%dT%H:%M:%S")
    return str(v)


def texto(v):
    return None if v is None else str(v)


def lista(v):
    if isinstance(v, list):
        return ", ".join(str(x) for x in v)
    return texto(v)


DDL = """
IF SCHEMA_ID(N'stg') IS NULL EXEC (N'CREATE SCHEMA stg');

DROP TABLE IF EXISTS stg.mongo_campanas;
CREATE TABLE stg.mongo_campanas (
    CampanaID NVARCHAR(50), NombreCampana NVARCHAR(150), Objetivo NVARCHAR(50),
    FechaInicio NVARCHAR(50), FechaFin NVARCHAR(50),
    Canales NVARCHAR(200), CategoriasPromocionadas NVARCHAR(250),
    PorcentajeDescuento NVARCHAR(50), CodigoCupon NVARCHAR(50),
    Presupuesto NVARCHAR(50), Responsable NVARCHAR(100));

DROP TABLE IF EXISTS stg.mongo_interacciones;
CREATE TABLE stg.mongo_interacciones (
    InteraccionID NVARCHAR(50), ClienteID NVARCHAR(50), CampanaID NVARCHAR(50),
    Canal NVARCHAR(50), Dispositivo NVARCHAR(50),
    CuponRedimido NVARCHAR(10),            -- campo del documento: 'true' / 'false' / NULL
    EventosJSON NVARCHAR(MAX));

IF OBJECT_ID(N'stg.ControlExtraccion') IS NULL      -- tabla compartida con Extraer_Perfiles_Mongo.py
CREATE TABLE stg.ControlExtraccion (
    Coleccion NVARCHAR(60) NOT NULL CONSTRAINT PK_stg_ControlExtraccion PRIMARY KEY,
    DocumentosOrigen INT NOT NULL, FilasCargadasStg INT NOT NULL, FechaExtraccion DATETIME2(0) NOT NULL);
"""


def insertar(cur, sql, filas):
    """Intenta fast_executemany; si el driver falla con NVARCHAR(MAX), cae a modo normal."""
    try:
        cur.fast_executemany = True
        cur.executemany(sql, filas)
    except Exception as e:
        print(f"  (fast_executemany fallo: {e.__class__.__name__}; se reintenta en modo normal)")
        cur.connection.rollback()
        cur.fast_executemany = False
        cur.executemany(sql, filas)


def main():
    a = args()
    base = f"FINALBI_DW_Grupo{a.grupo}"
    mdb = pymongo.MongoClient(a.mongo_uri, serverSelectionTimeoutMS=8000)[a.mongo_db]
    mdb.command("ping")
    cn = conectar_sql(a.server, base)
    cur = cn.cursor()
    cur.execute(DDL)
    cn.commit()

    # ---- campanas ---------------------------------------------------------
    docs = list(mdb["campanas"].find())
    filas = []
    for d in docs:
        ini, fin = d.get("fechaInicio"), d.get("fechaFin")
        # Las fechas de campana son datetime UTC; se guardan solo como fecha (yyyy-mm-dd)
        filas.append((
            texto(d.get("_id")), texto(d.get("nombre")), texto(d.get("objetivo")),
            ini.strftime("%Y-%m-%d") if isinstance(ini, datetime) else texto(ini),
            fin.strftime("%Y-%m-%d") if isinstance(fin, datetime) else texto(fin),
            lista(d.get("canales")), lista(d.get("categoriasPromocionadas")),
            texto(d.get("descuentoOfrecido")),            # <- el campo real se llama descuentoOfrecido
            texto(d.get("codigoCupon")),
            texto(d.get("presupuesto")),                  # a veces llega como texto '9.800.000'
            texto(d.get("responsable"))))                 # a veces falta
    insertar(cur, "INSERT INTO stg.mongo_campanas VALUES (?,?,?,?,?,?,?,?,?,?,?)", filas)
    cn.commit()
    n_camp = (len(docs), len(filas))

    # ---- interacciones ---------------------------------------------------
    filas, n_docs = [], 0
    for d in mdb["interacciones_marketing"].find():
        n_docs += 1
        ev = [{"tipo": e.get("tipo"), "fecha": f_iso(e.get("fecha"))} for e in d.get("eventos", [])]
        cup = d.get("cuponRedimido")
        filas.append((
            texto(d.get("_id")), texto(d.get("clienteId")), texto(d.get("campanaId")),
            texto(d.get("canal")), texto(d.get("dispositivo")),
            None if cup is None else ("true" if cup else "false"),
            json.dumps(ev, ensure_ascii=False)))
    insertar(cur, "INSERT INTO stg.mongo_interacciones VALUES (?,?,?,?,?,?,?)", filas)
    cn.commit()
    n_int = (n_docs, len(filas))

    # ---- control: Mongo vs staging (lo lee 08_Validacion.sql) ------------
    for nombre, (m, s), tabla in (("campanas", n_camp, "mongo_campanas"),
                                  ("interacciones_marketing", n_int, "mongo_interacciones")):
        cur.execute(f"SELECT COUNT(*) FROM stg.{tabla}")
        real = cur.fetchone()[0]
        cur.execute("DELETE FROM stg.ControlExtraccion WHERE Coleccion = ?", nombre)
        cur.execute("INSERT INTO stg.ControlExtraccion VALUES (?,?,?,SYSUTCDATETIME())", nombre, m, real)
        print(f"  {nombre}: Mongo={m}  staging={real}  {'OK' if m == real else 'ERROR'}")
    cn.commit()
    cn.close()
    print("Extraccion de Mongo terminada.")


if __name__ == "__main__":
    main()
