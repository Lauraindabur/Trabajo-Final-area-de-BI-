<#
 00_Ejecutar_Todo.ps1  ·  Corre TODO el pipeline, de principio a fin, sin intervencion manual.

 Uso (PowerShell, dentro de la carpeta BI_GrupoN):
     .\00_Ejecutar_Todo.ps1 -Grupo 4
 Opciones:
     -Server  "localhost\SQLEXPRESS"      (instancia de SQL Server)
     -MongoUri "mongodb://localhost:27017" (o la URI de Atlas; NO la escriban en archivos)
     -MongoDb "marketing_bi"
     -ConfiarCertificado                  (agrega -C a sqlcmd si su ODBC 18 lo exige)
     -IncluirExploracion                  (corre tambien 00_Exploracion_OLTP.sql)

 Requisitos: FINALBI_OLTP creada y poblada, MongoDB con marketing_bi cargada,
             sqlcmd, Python 3 con "pip install -r extraccion_mongo\requirements.txt".
 Los scripts dicen "GrupoN": aqui se reemplaza por "Grupo<N>" en copias temporales
 (carpeta logs\tmp); los originales no se modifican. Se guarda un log por paso en logs\.
#>
param(
    [Parameter(Mandatory = $true)][string]$Grupo,
    [string]$Server   = "localhost\SQLEXPRESS",
    [string]$MongoUri = "mongodb://localhost:27017",
    [string]$MongoDb  = "marketing_bi",
    [switch]$ConfiarCertificado,
    [switch]$IncluirExploracion
)
$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$logs = Join-Path $raiz "logs"
$tmp  = Join-Path $logs "tmp"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$utf8bom = New-Object System.Text.UTF8Encoding($true)

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) { throw "No se encontro sqlcmd en el PATH." }
$py = if (Get-Command python -ErrorAction SilentlyContinue) { "python" } elseif (Get-Command py -ErrorAction SilentlyContinue) { "py" } else { throw "No se encontro Python." }

function Invoke-Sql([string]$archivo) {
    $origen  = Join-Path $raiz "sql\$archivo"
    $copia   = Join-Path $tmp $archivo
    $texto   = [System.IO.File]::ReadAllText($origen, [System.Text.Encoding]::UTF8).Replace("GrupoN", "Grupo$Grupo")
    [System.IO.File]::WriteAllText($copia, $texto, $utf8bom)
    $log = Join-Path $logs ($archivo -replace "\.sql$", ".log")
    Write-Host ">> $archivo" -ForegroundColor Cyan
    $sqlArgs = @("-S", $Server, "-E", "-b", "-I", "-W", "-f", "65001", "-i", $copia)
    if ($ConfiarCertificado) { $sqlArgs += "-C" }
    & sqlcmd @sqlArgs 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) { throw "Fallo $archivo (revise $log). Se detiene el proceso." }
}

$inicio = Get-Date
if ($IncluirExploracion) { Invoke-Sql "00_Exploracion_OLTP.sql" }
Invoke-Sql "01_Crear_DW.sql"
Invoke-Sql "02_Staging_SQL.sql"
Invoke-Sql "02b_Staging_Perfiles_Mongo.sql"

foreach ($script in @("Extraer_Mongo.py", "Extraer_Perfiles_Mongo.py")) {
    Write-Host ">> $script" -ForegroundColor Cyan
    & $py (Join-Path $raiz "extraccion_mongo\$script") --grupo $Grupo --mongo-uri $MongoUri --mongo-db $MongoDb --server $Server 2>&1 |
        Tee-Object -FilePath (Join-Path $logs ($script -replace "\.py$", ".log"))
    if ($LASTEXITCODE -ne 0) { throw "Fallo $script (revise logs\)." }
}

Invoke-Sql "03_ETL_Tiempo_T9.sql"
Invoke-Sql "04_ETL_Dimensiones_y_Ventas.sql"
Invoke-Sql "05_ETL_Perfiles_T10_T14.sql"
Invoke-Sql "06_ETL_Marketing_T15_T18.sql"
Invoke-Sql "07_ETL_Atribucion_T19.sql"
Invoke-Sql "08_Validacion.sql"

Write-Host ("`nListo en {0:N0} s. Revise logs\08_Validacion.log: todos los controles deben decir OK." -f ((Get-Date) - $inicio).TotalSeconds) -ForegroundColor Green
