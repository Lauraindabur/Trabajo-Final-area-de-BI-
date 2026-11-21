"""
PARTE 3 · Extracción de perfiles_marketing (MongoDB) -> stg.PerfilesMarketing (SQL Server)

Por qué Python (pymongo + pyodbc):
  - Lee los documentos directamente de MongoDB, sin archivos intermedios.
  - Los campos anidados (consentimientos, fidelizacion) se aplanan a columnas, y los
    arreglos (intereses, encuestasNPS) se guardan como JSON para desanidarlos en SQL
    con OPENJSON. Así TODA la limpieza (T10-T14) queda en SQL y se puede revisar.
  - No se limpia nada aquí: el staging guarda el dato tal como vino del origen.

Uso:
  pip install pymongo pyodbc
  python extraer_perfiles_mongo.py
  (Si  SQL Server tiene otro nombre, cambia SQL_SERVER abajo o ejecuta:  python extraer_perfiles_mongo.py "localhost\\SQLEXPRESS")
Re-ejecutable: vacía stg.PerfilesMarketing antes de cargar.

Tenemos 3 coleccones con objetos anidados: perfiles marketing, interacciones marketing,capañas
QUE HACEMOS: 


1. recibe --grupo, la dirección de Mongo, el servidor SQL, y arma el nombre de la base (FINALBI_DW_Grupo4).
2. driver_sql() -> busca el driver ODBC más nuevo instalado (18, 17 o el antiguo).
Funciones auxiliares:
1. utc() quita la zona horaria de las fechas, sin convertirlas (se guardan en UTC).
2. a_texto() pasa cualquier valor a texto.
3. tipo() anota con qué tipo llegó el dato (int, string). Es la evidencia de T10 y T13.
4. a_json() convierte un arreglo en texto JSON.
5. fila(doc) (72-94): convierte un documento en una fila plana. Los objetos anidados se aplanan en columnas (consentimientos.email → ConsEmail, fidelizacion.nivel → FidNivel). Los arreglos (intereses, encuestasNPS) se guardan como texto JSON. Si falta fidelizacion, marca TieneFidelizacion = 0.

-> EN MAIN

1. Cuenta y lee los documentos de Mongo.
2.Se conecta a SQL Server, vacía stg.PerfilesMarketing (TRUNCATE) e inserta todo de golpe (fast_executemany).
3. Cuenta cuántas filas quedaron y las anota en stg.ControlExtraccion con un MERGE (actualiza si ya existe y, si no, inserta).
4. Si el conteo no coincide, el script falla con sys.exit("ERROR..."). Eso detiene el pipeline.
"""
import argparse
import json
import os
import sys
from datetime import datetime, timezone

import pyodbc
from pymongo import MongoClient

_a = argparse.ArgumentParser()
_a.add_argument("--grupo", required=True, help="numero del grupo, p. ej. 4")
_a.add_argument("--mongo-uri", default=os.getenv("MONGO_URI", "mongodb://localhost:27017"))
_a.add_argument("--mongo-db", default=os.getenv("MONGO_DB", "marketing_bi"))
_a.add_argument("--server", default=os.getenv("SQL_SERVER", r"localhost\SQLEXPRESS"))
_args = _a.parse_args()
MONGO_URI = _args.mongo_uri
MONGO_DB = _args.mongo_db
COLECCION = "perfiles_marketing"
SQL_SERVER = _args.server
SQL_DB = f"FINALBI_DW_Grupo{_args.grupo}"


def driver_sql():
    """Usa el driver ODBC más reciente instalado."""
    for d in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server", "SQL Server"):
        if d in pyodbc.drivers():
            return d
    raise RuntimeError("No hay driver ODBC de SQL Server instalado")


def utc(fecha):
    """pymongo devuelve datetime sin zona (en UTC). Se guarda en UTC, sin convertir."""
    return fecha.replace(tzinfo=None) if isinstance(fecha, datetime) else None


def a_texto(valor):
    return None if valor is None else str(valor)


def tipo(valor):
    """Tipo con el que llegó el dato desde MongoDB: int / string / ..."""
    if valor is None:
        return None
    return "string" if isinstance(valor, str) else type(valor).__name__


def a_json(valor):
    if valor is None:
        return None
    return json.dumps(valor, ensure_ascii=False, default=lambda d: d.isoformat() + "Z")


def fila(doc):
    cons = doc.get("consentimientos") or {}
    fid = doc.get("fidelizacion")
    cid = doc.get("clienteId")
    puntos = fid.get("puntos") if isinstance(fid, dict) else None
    return (
        str(doc["_id"]),
        a_texto(cid),
        tipo(cid),
        utc(doc.get("fechaActualizacion")),
        doc.get("origenRegistro"),
        cons.get("email"),
        cons.get("sms"),
        cons.get("whatsapp"),
        doc.get("canalPreferido"),
        a_json(doc.get("intereses")),
        1 if isinstance(fid, dict) else 0,
        fid.get("nivel") if isinstance(fid, dict) else None,
        a_texto(puntos),
        tipo(puntos),
        utc(fid.get("fechaInscripcion")) if isinstance(fid, dict) else None,
        a_json(doc.get("encuestasNPS")),
    )


def main():
    mongo = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
    col = mongo[MONGO_DB][COLECCION]
    total_origen = col.count_documents({})
    filas = [fila(d) for d in col.find({})]
    print(f"MongoDB {MONGO_DB}.{COLECCION}: {total_origen} documentos leídos")

    cn = pyodbc.connect(
        f"DRIVER={{{driver_sql()}}};SERVER={SQL_SERVER};DATABASE={SQL_DB};"
        "Trusted_Connection=yes;TrustServerCertificate=yes;"
    )
    cur = cn.cursor()
    cur.execute("TRUNCATE TABLE stg.PerfilesMarketing;")
    cur.fast_executemany = True
    cur.executemany(
        """INSERT INTO stg.PerfilesMarketing
           (MongoID, ClienteIdRaw, ClienteIdTipoOrigen, FechaActualizacionUTC, OrigenRegistro,
            ConsEmail, ConsSMS, ConsWhatsApp, CanalPreferido, InteresesJSON,
            TieneFidelizacion, FidNivel, FidPuntosRaw, FidPuntosTipoOrigen, FidFechaInscripcionUTC,
            EncuestasNPSJSON)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        filas,
    )
    cargadas = cur.execute("SELECT COUNT(*) FROM stg.PerfilesMarketing").fetchval()
    cur.execute(
        """MERGE stg.ControlExtraccion AS t
           USING (SELECT ? AS Coleccion, ? AS Doc, ? AS Filas, ? AS Fecha) AS s
           ON t.Coleccion = s.Coleccion
           WHEN MATCHED THEN UPDATE SET DocumentosOrigen = s.Doc, FilasCargadasStg = s.Filas, FechaExtraccion = s.Fecha
           WHEN NOT MATCHED THEN INSERT VALUES (s.Coleccion, s.Doc, s.Filas, s.Fecha);""",
        COLECCION, total_origen, cargadas, datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0),
    )
    cn.commit()
    print(f"SQL Server {SQL_DB}.stg.PerfilesMarketing: {cargadas} filas cargadas")
    if cargadas != total_origen:
        sys.exit("ERROR: el número de filas en stg no coincide con MongoDB")


if __name__ == "__main__":
    main()
