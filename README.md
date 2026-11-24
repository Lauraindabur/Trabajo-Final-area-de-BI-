# BI_GrupoN · Scripts del Data Warehouse

## Requisitos
- `FINALBI_OLTP` creada y poblada.
- MongoDB con la base `marketing_bi` cargada (`campanas`, `perfiles_marketing`, `interacciones_marketing`).
- Dependencias de Python: `pip install -r extraccion_mongo\requirements.txt`

## Cómo correrlo
En PowerShell, dentro de esta carpeta:

```powershell
.\00_Ejecutar_Todo.ps1 -Grupo 4
```

- Cambie `4` por el número real del grupo.
- Si Mongo está en Atlas, agregue `-MongoUri "mongodb+srv://usuario:clave@cluster/"` (no guarde la clave en ningún archivo).
- Al terminar, revise `logs\08_Validacion.log`: todos los controles deben decir **OK** y la sección 9 **COINCIDE**.

**A mano:** ejecute en este orden (reemplazando `GrupoN` por `Grupo<N>`):
`01`, `02`, `02b`, `Extraer_Mongo.py --grupo <N>`, `Extraer_Perfiles_Mongo.py --grupo <N>`, `03`, `04`, `05`, `06`, `07`, `08`.

## Pasos

| # | Archivo | Qué hace | Responsable |
|---|---------|----------|-------------|
| 00 | `00_Exploracion_OLTP.sql` | Conteos y calidad del OLTP (solo lee; opcional) | Persona 1 |
| 01 | `01_Crear_DW.sql` | Crea `FINALBI_DW_GrupoN`: 7 dimensiones, 2 hechos, miembro -1 | Persona 4 (Parte 2) |
| 02 | `02_Staging_SQL.sql` | Esquema `stg`, copia del OLTP, T1–T4 (geografía) | Persona 1 |
| 02b | `02b_Staging_Perfiles_Mongo.sql` | Tablas stg de perfiles y control de extracción | Persona 2 |
| – | `Extraer_Mongo.py` | Campañas e interacciones → `stg.mongo_*` + conteos de control | Marketing |
| – | `Extraer_Perfiles_Mongo.py` | Perfiles → `stg.PerfilesMarketing` | Persona 2 |
| 03 | `03_ETL_Tiempo_T9.sql` | DIM_Tiempo 2024-2025 | Persona 4 (T9) |
| 04 | `04_ETL_Dimensiones_y_Ventas.sql` | Dimensiones SQL y FACT_Ventas (T5–T8) | Persona 1 |
| 05 | `05_ETL_Perfiles_T10_T14.sql` | Perfiles → DIM_Cliente (T10–T14) | Persona 2 |
| 06 | `06_ETL_Marketing_T15_T18.sql` | Campañas e interacciones (T15–T18) | Marketing |
| 07 | `07_ETL_Atribucion_T19.sql` | Atribución de ventas a campañas | Persona 4 (T19) |
| 08 | `08_Validacion.sql` | Controles OK/ERROR, uso del -1 y calidad | Persona 4 (Parte 4) |

## Cambios sobre el código original
- **Extraer_Mongo.py**
  - Leía `porcentajeDescuento`/`descuento`, que no existen (el campo real es `descuentoOfrecido`): todos los descuentos salían 0.
  - No traía `cuponRedimido` (1.359 verdaderos) ni los perfiles.
  - La clave de Atlas estaba escrita en el código: ahora la URI y el servidor se pasan por parámetro.
- **06 (MarketingP3.sql)**
  - `CuponRedimido` buscaba un evento `cupon_redimido` inexistente (siempre 0): ahora usa el campo `cuponRedimido`.
  - Las fechas dd/mm/aaaa se convierten con estilo 103 explícito; con `TRY_CAST` dependía del idioma del servidor y 294 fechas podían quedar con día y mes cambiados.
  - `TiempoKey` sin `FORMAT` (más rápido).
- **Perfiles (Persona 2)**
  - P2_01, P2_02 y P2_03 entran sin cambiar la lógica.
  - Solo se parametrizó el `.py` (grupo, servidor, URI); la validación P2_03 es la sección 10 del 08.
  - Ambas extracciones comparten `stg.ControlExtraccion`.
- **04 (02_ETL.sql)**: se quitó la carga de respaldo de DIM_Tiempo (duplicaba T9, ahora en el 03).
- **08**: une la validación de ventas y marketing; agrega OK/ERROR, uso del -1 en ambas hechos, DIM_Tiempo, geografía y T19.

## Supuestos
- Las fechas de texto de Mongo se tratan como UTC igual que las ISO; todas se pasan a hora de Colombia (UTC-5).
- T19: último clic del cliente en los 7 días anteriores al pedido (por día); se atribuye el pedido completo.
- En `redes_sociales` solo existe el evento `impresion`: las tasas de entrega/apertura se calculan sobre Email, SMS y WhatsApp.
- Los valores de "Referencia" de la sección 9 salen de los JSON entregados (iguales para todos los grupos).
