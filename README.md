# BI_GrupoN · scripts del Data Warehouse (de principio a fin)

## Cómo correrlo
1. Tener `FINALBI_OLTP` creada y poblada, y MongoDB con la base `marketing_bi` cargada (`campanas`, `perfiles_marketing`, `interacciones_marketing`).
2. `pip install -r extraccion_mongo\requirements.txt`
3. En PowerShell, dentro de esta carpeta:
   `.\00_Ejecutar_Todo.ps1 -Grupo 4`   (cambie 4 por el número real del grupo)
   Si Mongo está en Atlas: `-MongoUri "mongodb+srv://usuario:clave@cluster/"` (no guardar la clave en ningún archivo).
4. Revisar `logs\08_Validacion.log`: todos los controles deben decir **OK** (y la sección 9 **COINCIDE**).

Si prefiere correrlo a mano, ejecute en este orden (reemplazando `GrupoN` por `Grupo<N>`): 01, 02, 02b, `Extraer_Mongo.py --grupo <N>`, `Extraer_Perfiles_Mongo.py --grupo <N>`, 03, 04, 05, 06, 07, 08.

## Qué hace cada paso
| # | Archivo | Qué hace | Responsable |
|---|---------|----------|-------------|
| 00 | `00_Exploracion_OLTP.sql` | Conteos y calidad del OLTP (solo lee; opcional) | Persona 1 |
| 01 | `01_Crear_DW.sql` | Crea `FINALBI_DW_GrupoN`: 7 dimensiones, 2 hechos, miembro -1 | Persona 4 (Parte 2) |
| 02 | `02_Staging_SQL.sql` | Esquema `stg`, copia del OLTP, T1, T2, T3 y T4 (geografía) | Persona 1 |
| 02b | `02b_Staging_Perfiles_Mongo.sql` | Tablas stg de perfiles y control de extracción | Persona 2 |
| – | `Extraer_Mongo.py` | Campañas e interacciones → `stg.mongo_*` + conteos de control | Persona de marketing (corregido) |
| – | `Extraer_Perfiles_Mongo.py` | Perfiles → `stg.PerfilesMarketing` | Persona 2 |
| 03 | `03_ETL_Tiempo_T9.sql` | DIM_Tiempo 2024-2025 | Persona 4 (T9) |
| 04 | `04_ETL_Dimensiones_y_Ventas.sql` | Dimensiones SQL, FACT_Ventas (T5–T8) | Persona 1 |
| 05 | `05_ETL_Perfiles_T10_T14.sql` | Perfiles → DIM_Cliente (T10–T14) | Persona 2 |
| 06 | `06_ETL_Marketing_T15_T18.sql` | Campañas, interacciones (T15–T18) | Persona de marketing (corregido) |
| 07 | `07_ETL_Atribucion_T19.sql` | Atribución de ventas a campañas | Persona 4 (T19) |
| 08 | `08_Validacion.sql` | Todos los controles OK/ERROR + punto 3 (-1) + calidad | Persona 4 (Parte 4) |

## Cambios hechos sobre el código original
- **Extraer_Mongo.py**: leía `porcentajeDescuento`/`descuento`, campos que no existen (el real es `descuentoOfrecido`), y todos los descuentos salían 0. Tampoco traía `cuponRedimido` (campo del documento, 1.359 verdaderos) ni los perfiles. Tenía la clave de Atlas escrita en el código: ahora la URI y el servidor se pasan por parámetro.
- **06 (MarketingP3.sql)**: `CuponRedimido` buscaba un tipo de evento `cupon_redimido` que no existe (siempre 0): ahora usa el campo `cuponRedimido`. Las fechas de texto dd/mm/aaaa se convierten con estilo 103 explícito (con `TRY_CAST` dependía del idioma del servidor y 294 fechas podían quedar con día y mes cambiados). `TiempoKey` sin `FORMAT` (más rápido).
- **Perfiles (Persona 2)**: sus archivos P2_01, P2_02 y P2_03 entran sin cambiar la lógica; solo se parametrizó el .py (grupo, servidor, URI) y la validación P2_03 es la sección 10 del 08. Las dos extracciones comparten la tabla `stg.ControlExtraccion`.
- **04 (02_ETL.sql)**: se quitó la carga de respaldo de DIM_Tiempo (duplicaba T9, ahora hecho en el 03).
- **08**: une la validación de ventas y la de marketing, agrega OK/ERROR, el uso del -1 en ambas hechos, DIM_Tiempo, geografía y T19.

## Supuestos
- Las fechas de texto de Mongo se tratan como UTC igual que las ISO; todas se pasan a hora de Colombia (UTC-5).
- T19: último clic del cliente en los 7 días anteriores al pedido (por día); se atribuye el pedido completo.
- En `redes_sociales` solo existe el evento `impresion`: las tasas de entrega/apertura se calculan sobre Email, SMS y WhatsApp.
- Los valores de "Referencia" de la sección 9 salen de los JSON entregados (iguales para todos los grupos).
