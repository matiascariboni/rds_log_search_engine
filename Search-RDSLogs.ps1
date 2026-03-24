#Requires -Version 5.1
<#
.SYNOPSIS
    Busqueda avanzada en logs de auditoria de RDS (con busqueda recursiva).
.DESCRIPTION
    Formato esperado de logs (sin cabeceras):
    20260108 06:38:12,ip-10-20-3-74,mqtt-decoder,ec2-107-21-196-50.compute-1.amazonaws.com,1016648,0,DISCONNECT,ENV000_MasterCommonData,,0,TCP/IP
    
    Campos: DateTime,Server,Application,Host,Id1,Id2,Action,Database,Query,Flag,Protocol
.EXAMPLE
    .\Search-RDSLogs.ps1 -Environment prod -SearchTerms "mqtt-decoder"
.EXAMPLE
    .\Search-RDSLogs.ps1 -SearchTerms "mqtt-decoder","things-watchdog" -MatchAll
.EXAMPLE
    .\Search-RDSLogs.ps1 -Interactive
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('prod', 'preprod', 'both')]
    [string]$Environment = 'both',

    [Parameter(Mandatory=$false)]
    [string[]]$SearchTerms,

    [Parameter(Mandatory=$false)]
    [switch]$MatchAll,

    [Parameter(Mandatory=$false)]
    [switch]$CaseSensitive,

    [Parameter(Mandatory=$false)]
    [string]$DateFrom,

    [Parameter(Mandatory=$false)]
    [string]$DateTo,

    [Parameter(Mandatory=$false)]
    [string]$Application,

    [Parameter(Mandatory=$false)]
    [string]$Database,

    [Parameter(Mandatory=$false)]
    [ValidateSet('QUERY', 'CONNECT', 'DISCONNECT', 'INSERT', 'UPDATE', 'DELETE', 'CALL')]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [string]$OutputFile,

    [Parameter(Mandatory=$false)]
    [int]$MaxResults = 0,

    [Parameter(Mandatory=$false)]
    [switch]$ShowStats,

    [Parameter(Mandatory=$false)]
    [ValidateSet('CSV', 'JSON', 'TXT')]
    [string]$ExportFormat = 'CSV',

    [Parameter(Mandatory=$false)]
    [switch]$Interactive,

    [Parameter(Mandatory=$false)]
    [switch]$ShowDebug
)

# Colores para output
$script:Colors = @{
    Success = 'Green'
    Warning = 'Yellow'
    Error = 'Red'
    Info = 'Cyan'
    Highlight = 'Magenta'
    Debug = 'DarkGray'
}

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = 'White',
        [switch]$NoNewline
    )

    $params = @{
        Object = $Message
        ForegroundColor = $Color
    }
    if ($NoNewline) { $params['NoNewline'] = $true }

    Write-Host @params
}

function Write-DebugMessage {
    param([string]$Message)
    
    if ($script:DebugMode) {
        Write-ColorOutput "[DEBUG] $Message" -Color $Colors.Debug
    }
}

function Show-Banner {
    Write-Host ""
    Write-ColorOutput "============================================================" -Color $Colors.Info
    Write-ColorOutput "           RDS LOG SEARCH ENGINE v2.0 (Fixed)              " -Color $Colors.Info
    Write-ColorOutput "           Busqueda Avanzada de Logs                        " -Color $Colors.Info
    Write-ColorOutput "============================================================" -Color $Colors.Info
    Write-Host ""
}

function Test-LogStructure {
    param([string]$BasePath)

    $environments = @('prod', 'preprod')
    $issues = @()

    foreach ($env in $environments) {
        $envPath = Join-Path $BasePath $env
        if (-not (Test-Path $envPath)) {
            $issues += "No existe el directorio: $envPath"
        } else {
            $logFiles = Get-ChildItem -Path $envPath -Filter "server_audit.log*" -File -Recurse -ErrorAction SilentlyContinue
            if ($logFiles.Count -eq 0) {
                $issues += "No se encontraron archivos de log en: $envPath (busqueda recursiva)"
            } else {
                Write-ColorOutput "  [OK] Encontrados $($logFiles.Count) archivos de log en $env" -Color $Colors.Success
                $folders = $logFiles | ForEach-Object { Split-Path $_.FullName -Parent } | Select-Object -Unique
                foreach ($folder in $folders) {
                    $relativePath = $folder.Replace($BasePath, "").TrimStart('\', '/')
                    Write-ColorOutput "    - $relativePath" -Color $Colors.Info
                }
            }
        }
    }

    return $issues
}

function Parse-LogLine {
    param([string]$Line)

    # Formato REAL de los logs:
    # 20260108 06:38:12,ip-10-20-3-74,mqtt-decoder,ec2-107-21-196-50.compute-1.amazonaws.com,1016648,0,DISCONNECT,ENV000_MasterCommonData,,0,TCP/IP
    # Campo 0: "20260108 06:38:12" (fecha y hora JUNTAS en el mismo campo)
    # Campo 1: server (ip-10-20-3-74)
    # Campo 2: application (mqtt-decoder)
    # Campo 3: host 
    # Campo 4: id1
    # Campo 5: id2
    # Campo 6: action (DISCONNECT, QUERY, CONNECT, etc.)
    # Campo 7: database
    # Campo 8: query (puede contener comas, por eso limitamos el split)
    # Campo 9: flag
    # Campo 10: protocol

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $null
    }

    # Dividimos por coma, máximo 12 partes para capturar todo el query aunque tenga comas
    $parts = $Line -split ',', 12

    if ($parts.Count -lt 8) {
        Write-DebugMessage "Linea con menos de 8 campos: $($parts.Count) campos"
        return $null
    }

    try {
        # El primer campo contiene FECHA Y HORA juntas: "20260108 06:38:12"
        $dateTimeStr = $parts[0].Trim()
        
        # Intentar parsear con el formato correcto
        $dateTime = $null
        
        # Formato: "yyyyMMdd HH:mm:ss"
        if ($dateTimeStr -match '^\d{8}\s+\d{2}:\d{2}:\d{2}') {
            try {
                $dateTime = [datetime]::ParseExact($dateTimeStr, "yyyyMMdd HH:mm:ss", $null)
            } catch {
                Write-DebugMessage "Error parseando fecha con formato 'yyyyMMdd HH:mm:ss': $dateTimeStr"
            }
        }
        
        # Si no funcionó, intentar otros formatos comunes
        if (-not $dateTime) {
            try {
                $dateTime = [datetime]::Parse($dateTimeStr)
            } catch {
                Write-DebugMessage "Error parseando fecha generico: $dateTimeStr"
                # Si no podemos parsear la fecha, aún podemos procesar la línea
                $dateTime = [datetime]::MinValue
            }
        }

        $result = [PSCustomObject]@{
            DateTime = $dateTime
            DateTimeStr = $dateTimeStr
            Server = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }
            Application = if ($parts.Count -gt 2) { $parts[2].Trim() } else { "" }
            Host = if ($parts.Count -gt 3) { $parts[3].Trim() } else { "" }
            Id1 = if ($parts.Count -gt 4) { $parts[4].Trim() } else { "" }
            Id2 = if ($parts.Count -gt 5) { $parts[5].Trim() } else { "" }
            Action = if ($parts.Count -gt 6) { $parts[6].Trim() } else { "" }
            Database = if ($parts.Count -gt 7) { $parts[7].Trim() } else { "" }
            Query = if ($parts.Count -gt 8) { $parts[8].Trim() } else { "" }
            Flag = if ($parts.Count -gt 9) { $parts[9].Trim() } else { "" }
            Protocol = if ($parts.Count -gt 10) { $parts[10].Trim() } else { "" }
            RawLine = $Line
        }

        Write-DebugMessage "Parsed OK: App=$($result.Application), Action=$($result.Action)"
        return $result

    } catch {
        Write-DebugMessage "Excepcion parseando linea: $_"
        return $null
    }
}

function Test-LogLineMatch {
    param(
        [PSCustomObject]$ParsedLine,
        [hashtable]$Filters
    )

    if (-not $ParsedLine) { 
        return $false 
    }

    # Filtro por fecha desde
    if ($Filters.DateFrom -and $ParsedLine.DateTime -ne [datetime]::MinValue) {
        if ($ParsedLine.DateTime -lt $Filters.DateFrom) {
            return $false
        }
    }
    
    # Filtro por fecha hasta
    if ($Filters.DateTo -and $ParsedLine.DateTime -ne [datetime]::MinValue) {
        if ($ParsedLine.DateTime -gt $Filters.DateTo) {
            return $false
        }
    }

    # Filtro por aplicación
    if ($Filters.Application) {
        if ($ParsedLine.Application -notlike "*$($Filters.Application)*") {
            return $false
        }
    }

    # Filtro por base de datos
    if ($Filters.Database) {
        if ($ParsedLine.Database -notlike "*$($Filters.Database)*") {
            return $false
        }
    }

    # Filtro por acción
    if ($Filters.Action) {
        if ($ParsedLine.Action -ne $Filters.Action) {
            return $false
        }
    }

    # Filtro por términos de búsqueda
    if ($Filters.SearchTerms -and $Filters.SearchTerms.Count -gt 0) {
        $line = $ParsedLine.RawLine

        if ($Filters.MatchAll) {
            # Modo AND: todos los términos deben estar presentes
            foreach ($term in $Filters.SearchTerms) {
                $matched = $false
                if ($Filters.CaseSensitive) {
                    $matched = $line -clike "*$term*"
                } else {
                    $matched = $line -like "*$term*"
                }
                if (-not $matched) {
                    return $false
                }
            }
        } else {
            # Modo OR: al menos un término debe estar presente
            $found = $false
            foreach ($term in $Filters.SearchTerms) {
                if ($Filters.CaseSensitive) {
                    if ($line -clike "*$term*") {
                        $found = $true
                        break
                    }
                } else {
                    if ($line -like "*$term*") {
                        $found = $true
                        break
                    }
                }
            }
            if (-not $found) {
                return $false
            }
        }
    }

    return $true
}

function Search-LogFiles {
    param(
        [string[]]$LogFiles,
        [hashtable]$Filters,
        [string]$EnvironmentName
    )

    $results = [System.Collections.ArrayList]::new()
    $totalLines = 0
    $matchedLines = 0
    $parseErrors = 0

    Write-ColorOutput "Buscando en ambiente: $EnvironmentName" -Color $Colors.Info
    Write-ColorOutput "Archivos a procesar: $($LogFiles.Count)" -Color $Colors.Info

    $fileCount = 0
    foreach ($logFile in $LogFiles) {
        $fileCount++
        $fileName = Split-Path $logFile -Leaf
        $relativePath = $logFile.Replace($script:scriptDir, "").TrimStart('\', '/')

        Write-Progress -Activity "Procesando logs de $EnvironmentName" `
                       -Status "Archivo $fileCount de $($LogFiles.Count): $fileName" `
                       -PercentComplete (($fileCount / $LogFiles.Count) * 100)

        try {
            # Usar StreamReader para mejor rendimiento en archivos grandes
            $reader = [System.IO.StreamReader]::new($logFile, [System.Text.Encoding]::UTF8)
            $lineNumber = 0
            
            while ($null -ne ($line = $reader.ReadLine())) {
                $lineNumber++
                $totalLines++

                if ([string]::IsNullOrWhiteSpace($line)) { 
                    continue 
                }

                $parsed = Parse-LogLine -Line $line

                if (-not $parsed) {
                    $parseErrors++
                    continue
                }

                if (Test-LogLineMatch -ParsedLine $parsed -Filters $Filters) {
                    $matchedLines++

                    [void]$results.Add([PSCustomObject]@{
                        Environment = $EnvironmentName
                        File = $fileName
                        FilePath = $relativePath
                        LineNumber = $lineNumber
                        DateTime = $parsed.DateTime
                        DateTimeStr = $parsed.DateTimeStr
                        Server = $parsed.Server
                        Application = $parsed.Application
                        Host = $parsed.Host
                        Action = $parsed.Action
                        Database = $parsed.Database
                        Query = $parsed.Query
                        Flag = $parsed.Flag
                        Protocol = $parsed.Protocol
                    })

                    if ($Filters.MaxResults -gt 0 -and $matchedLines -ge $Filters.MaxResults) {
                        Write-ColorOutput "Limite de resultados alcanzado: $($Filters.MaxResults)" -Color $Colors.Warning
                        $reader.Close()
                        break
                    }
                }
            }

            $reader.Close()

            if ($Filters.MaxResults -gt 0 -and $matchedLines -ge $Filters.MaxResults) {
                break
            }

        } catch {
            Write-ColorOutput "Error al procesar $logFile : $_" -Color $Colors.Error
        }
    }

    Write-Progress -Activity "Procesando logs de $EnvironmentName" -Completed

    if ($parseErrors -gt 0 -and $script:DebugMode) {
        Write-ColorOutput "  Lineas con errores de parseo: $parseErrors" -Color $Colors.Warning
    }

    return @{
        Results = $results
        TotalLines = $totalLines
        MatchedLines = $matchedLines
        ParseErrors = $parseErrors
    }
}

function Export-Results {
    param(
        [array]$Results,
        [string]$OutputPath,
        [string]$Format
    )

    Write-ColorOutput "Exportando $($Results.Count) resultados a $OutputPath..." -Color $Colors.Info

    try {
        switch ($Format) {
            'CSV' {
                $Results | Select-Object Environment, FilePath, LineNumber, DateTimeStr, Server, Application, Host, Action, Database, Query, Flag, Protocol |
                    Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
            }
            'JSON' {
                $Results | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
            }
            'TXT' {
                $Results | ForEach-Object {
                    "[$($_.Environment)] $($_.DateTimeStr) - $($_.Application) - $($_.Action)"
                    "  Server: $($_.Server)"
                    "  Host: $($_.Host)"
                    "  DB: $($_.Database)"
                    "  Query: $($_.Query)"
                    "  File: $($_.FilePath):$($_.LineNumber)"
                    ""
                } | Out-File -FilePath $OutputPath -Encoding UTF8
            }
        }
        Write-ColorOutput "Resultados exportados exitosamente a: $OutputPath" -Color $Colors.Success
    } catch {
        Write-ColorOutput "Error al exportar resultados: $_" -Color $Colors.Error
    }
}

function Show-Statistics {
    param([hashtable]$Stats)

    Write-Host ""
    Write-ColorOutput "=============== ESTADISTICAS ===============" -Color $Colors.Highlight
    Write-ColorOutput "Lineas totales procesadas: $($Stats.TotalLines)" -Color White
    Write-ColorOutput "Lineas que coinciden: $($Stats.MatchedLines)" -Color White
    
    if ($Stats.ParseErrors -gt 0) {
        Write-ColorOutput "Lineas con errores de parseo: $($Stats.ParseErrors)" -Color $Colors.Warning
    }

    if ($Stats.TotalLines -gt 0) {
        $percentage = ($Stats.MatchedLines / $Stats.TotalLines) * 100
        Write-ColorOutput ("Porcentaje de coincidencia: {0:N4}%" -f $percentage) -Color White
    }

    if ($Stats.Results.Count -gt 0) {
        $byEnv = $Stats.Results | Group-Object Environment
        Write-Host ""
        Write-ColorOutput "Resultados por ambiente:" -Color $Colors.Info
        foreach ($group in $byEnv) {
            Write-ColorOutput "  $($group.Name): $($group.Count)" -Color White
        }

        $byAction = $Stats.Results | Group-Object Action
        Write-Host ""
        Write-ColorOutput "Resultados por accion:" -Color $Colors.Info
        foreach ($group in $byAction) {
            Write-ColorOutput "  $($group.Name): $($group.Count)" -Color White
        }

        $byApp = $Stats.Results | Group-Object Application | Sort-Object Count -Descending | Select-Object -First 10
        Write-Host ""
        Write-ColorOutput "Top 10 aplicaciones:" -Color $Colors.Info
        foreach ($group in $byApp) {
            Write-ColorOutput "  $($group.Name): $($group.Count)" -Color White
        }
    }

    Write-ColorOutput "============================================" -Color $Colors.Highlight
}

function Start-InteractiveMode {
    Write-ColorOutput "`n=== MODO INTERACTIVO ===" -Color $Colors.Highlight
    Write-Host ""

    Write-ColorOutput "Seleccione el ambiente a buscar:" -Color $Colors.Info
    Write-Host "  1. Produccion (prod)"
    Write-Host "  2. Pre-produccion (preprod)"
    Write-Host "  3. Ambos"
    $envChoice = Read-Host "Opcion (1-3)"

    $env = switch ($envChoice) {
        "1" { "prod" }
        "2" { "preprod" }
        "3" { "both" }
        default { "both" }
    }

    Write-ColorOutput "`nDesea buscar terminos especificos? (S/N)" -Color $Colors.Info
    $searchChoice = Read-Host

    $terms = @()
    $matchAll = $false

    if ($searchChoice -eq "S" -or $searchChoice -eq "s") {
        Write-ColorOutput "Ingrese los terminos de busqueda (separados por coma):" -Color $Colors.Info
        $termsInput = Read-Host
        $terms = $termsInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

        if ($terms.Count -gt 1) {
            Write-ColorOutput "Buscar lineas con TODOS los terminos (AND) o CUALQUIER termino (OR)?" -Color $Colors.Info
            Write-Host "  1. TODOS (AND)"
            Write-Host "  2. CUALQUIERA (OR)"
            $logicChoice = Read-Host "Opcion (1-2)"
            $matchAll = ($logicChoice -eq "1")
        }
    }

    Write-ColorOutput "`nDesea aplicar filtros adicionales? (S/N)" -Color $Colors.Info
    $filterChoice = Read-Host

    $params = @{
        Environment = $env
        ShowStats = $true
    }

    if ($terms.Count -gt 0) {
        $params['SearchTerms'] = $terms
        if ($matchAll) {
            $params['MatchAll'] = $true
        }
    }

    if ($filterChoice -eq "S" -or $filterChoice -eq "s") {
        Write-ColorOutput "`nAplicacion (dejar vacio para omitir):" -Color $Colors.Info
        $app = Read-Host
        if ($app) { $params['Application'] = $app }

        Write-ColorOutput "Base de datos (dejar vacio para omitir):" -Color $Colors.Info
        $db = Read-Host
        if ($db) { $params['Database'] = $db }

        Write-ColorOutput "Accion (QUERY, CONNECT, DISCONNECT, etc. - dejar vacio para omitir):" -Color $Colors.Info
        $action = Read-Host
        if ($action) { $params['Action'] = $action }

        Write-ColorOutput "Fecha desde (yyyy-MM-dd - dejar vacio para omitir):" -Color $Colors.Info
        $dateFrom = Read-Host
        if ($dateFrom) { $params['DateFrom'] = $dateFrom }

        Write-ColorOutput "Fecha hasta (yyyy-MM-dd - dejar vacio para omitir):" -Color $Colors.Info
        $dateTo = Read-Host
        if ($dateTo) { $params['DateTo'] = $dateTo }
    }

    Write-ColorOutput "`nLimite de resultados? (0 = sin limite):" -Color $Colors.Info
    $maxResults = Read-Host
    if ($maxResults) { $params['MaxResults'] = [int]$maxResults }

    Write-ColorOutput "`nExportar resultados? (S/N)" -Color $Colors.Info
    $exportChoice = Read-Host

    if ($exportChoice -eq "S" -or $exportChoice -eq "s") {
        Write-ColorOutput "Nombre del archivo (sin extension):" -Color $Colors.Info
        $fileName = Read-Host

        Write-ColorOutput "Formato (CSV/JSON/TXT):" -Color $Colors.Info
        $format = Read-Host
        if (-not $format) { $format = "CSV" }

        $extension = $format.ToLower()
        $params['OutputFile'] = "$fileName.$extension"
        $params['ExportFormat'] = $format.ToUpper()
    }

    Write-ColorOutput "`n=== INICIANDO BUSQUEDA ===`n" -Color $Colors.Success

    return $params
}

# ==================== MAIN ====================

# Guardar modo debug
$script:DebugMode = $ShowDebug.IsPresent

# Procesar modo interactivo
if ($Interactive) {
    $interactiveParams = Start-InteractiveMode

    if ($interactiveParams) {
        if ($interactiveParams['Environment']) { $Environment = $interactiveParams['Environment'] }
        if ($interactiveParams['SearchTerms']) { $SearchTerms = $interactiveParams['SearchTerms'] }
        if ($interactiveParams['MatchAll']) { $MatchAll = $true }
        if ($interactiveParams['Application']) { $Application = $interactiveParams['Application'] }
        if ($interactiveParams['Database']) { $Database = $interactiveParams['Database'] }
        if ($interactiveParams['Action']) { $Action = $interactiveParams['Action'] }
        if ($interactiveParams['DateFrom']) { $DateFrom = $interactiveParams['DateFrom'] }
        if ($interactiveParams['DateTo']) { $DateTo = $interactiveParams['DateTo'] }
        if ($interactiveParams['MaxResults']) { $MaxResults = $interactiveParams['MaxResults'] }
        if ($interactiveParams['OutputFile']) { $OutputFile = $interactiveParams['OutputFile'] }
        if ($interactiveParams['ExportFormat']) { $ExportFormat = $interactiveParams['ExportFormat'] }
        if ($interactiveParams['ShowStats']) { $ShowStats = $true }
    }
}

Show-Banner

# Determinar directorio base
$script:scriptDir = $PSScriptRoot
if (-not $script:scriptDir) {
    $script:scriptDir = (Get-Location).Path
}

Write-ColorOutput "Directorio base: $script:scriptDir" -Color $Colors.Info
Write-Host ""

# Validar estructura
$structureIssues = Test-LogStructure -BasePath $script:scriptDir
if ($structureIssues.Count -gt 0) {
    Write-ColorOutput "Problemas encontrados:" -Color $Colors.Error
    $structureIssues | ForEach-Object {
        Write-ColorOutput "  - $_" -Color $Colors.Error
    }
    exit 1
}

# Construir filtros
$filters = @{
    SearchTerms = $SearchTerms
    MatchAll = $MatchAll.IsPresent
    CaseSensitive = $CaseSensitive.IsPresent
    Application = $Application
    Database = $Database
    Action = $Action
    MaxResults = $MaxResults
}

# Parsear fechas
if ($DateFrom) {
    try {
        $filters.DateFrom = [datetime]::Parse($DateFrom)
        Write-ColorOutput "Fecha desde: $($filters.DateFrom.ToString('yyyy-MM-dd HH:mm:ss'))" -Color $Colors.Info
    } catch {
        Write-ColorOutput "Formato de fecha invalido para DateFrom: $DateFrom" -Color $Colors.Error
        exit 1
    }
}

if ($DateTo) {
    try {
        $filters.DateTo = [datetime]::Parse($DateTo).AddDays(1).AddSeconds(-1)  # Final del día
        Write-ColorOutput "Fecha hasta: $($filters.DateTo.ToString('yyyy-MM-dd HH:mm:ss'))" -Color $Colors.Info
    } catch {
        Write-ColorOutput "Formato de fecha invalido para DateTo: $DateTo" -Color $Colors.Error
        exit 1
    }
}

# Mostrar criterios de búsqueda
Write-Host ""
Write-ColorOutput "=============== CRITERIOS DE BUSQUEDA ===============" -Color $Colors.Highlight
Write-ColorOutput "Ambiente(s): $Environment" -Color $Colors.Highlight

if ($SearchTerms) {
    $termsStr = $SearchTerms -join ', '
    $logic = if ($MatchAll) { "AND" } else { "OR" }
    Write-ColorOutput "Terminos ($logic): $termsStr" -Color $Colors.Highlight
}

if ($Application) {
    Write-ColorOutput "Aplicacion: $Application" -Color $Colors.Highlight
}

if ($Database) {
    Write-ColorOutput "Base de datos: $Database" -Color $Colors.Highlight
}

if ($Action) {
    Write-ColorOutput "Accion: $Action" -Color $Colors.Highlight
}

if ($CaseSensitive) {
    Write-ColorOutput "Busqueda sensible a mayusculas/minusculas: Si" -Color $Colors.Highlight
}

Write-ColorOutput "=====================================================" -Color $Colors.Highlight
Write-Host ""

# Determinar ambientes a buscar
$environmentsToSearch = @()
switch ($Environment) {
    'prod' { $environmentsToSearch += 'prod' }
    'preprod' { $environmentsToSearch += 'preprod' }
    'both' { $environmentsToSearch += @('prod', 'preprod') }
}

$allResults = [System.Collections.ArrayList]::new()
$totalStats = @{
    TotalLines = 0
    MatchedLines = 0
    ParseErrors = 0
}

# Ejecutar búsqueda en cada ambiente
foreach ($env in $environmentsToSearch) {
    $envPath = Join-Path $script:scriptDir $env
    $logFiles = Get-ChildItem -Path $envPath -Filter "server_audit.log*" -File -Recurse -ErrorAction SilentlyContinue | 
                Sort-Object FullName | 
                Select-Object -ExpandProperty FullName

    if ($logFiles.Count -eq 0) {
        Write-ColorOutput "No se encontraron archivos de log en $env" -Color $Colors.Warning
        continue
    }

    $searchResult = Search-LogFiles -LogFiles $logFiles -Filters $filters -EnvironmentName $env

    foreach ($r in $searchResult.Results) {
        [void]$allResults.Add($r)
    }
    
    $totalStats.TotalLines += $searchResult.TotalLines
    $totalStats.MatchedLines += $searchResult.MatchedLines
    $totalStats.ParseErrors += $searchResult.ParseErrors

    Write-ColorOutput "Encontrados $($searchResult.MatchedLines) resultados en $env`n" -Color $Colors.Success
}

# Mostrar resultados
if ($allResults.Count -eq 0) {
    Write-ColorOutput "No se encontraron resultados que coincidan con los criterios de busqueda" -Color $Colors.Warning
    
    if ($totalStats.TotalLines -gt 0) {
        Write-ColorOutput "  (Se procesaron $($totalStats.TotalLines) lineas en total)" -Color $Colors.Info
    }
} else {
    Write-Host ""
    Write-ColorOutput "=============== RESULTADOS ===============" -Color $Colors.Success
    Write-ColorOutput "Total de coincidencias: $($allResults.Count)" -Color $Colors.Success
    Write-ColorOutput "==========================================" -Color $Colors.Success
    Write-Host ""

    $displayLimit = [Math]::Min($allResults.Count, 10)

    Write-ColorOutput "Mostrando los primeros $displayLimit resultados:`n" -Color $Colors.Info

    $allResults | Select-Object -First $displayLimit | ForEach-Object {
        Write-ColorOutput "[$($_.Environment)] $($_.DateTimeStr) - $($_.Application) - $($_.Action)" -Color $Colors.Highlight
        Write-ColorOutput "  Server: $($_.Server)" -Color White
        Write-ColorOutput "  DB: $($_.Database)" -Color White
        if ($_.Query) {
            $queryPreview = if ($_.Query.Length -gt 100) { $_.Query.Substring(0, 100) + "..." } else { $_.Query }
            Write-ColorOutput "  Query: $queryPreview" -Color Gray
        }
        Write-ColorOutput "  Archivo: $($_.FilePath):$($_.LineNumber)" -Color DarkGray
        Write-Host ""
    }

    if ($allResults.Count -gt 10) {
        Write-ColorOutput "... y $($allResults.Count - 10) resultados mas" -Color $Colors.Info
    }
}

# Exportar si se especificó
if ($OutputFile -and $allResults.Count -gt 0) {
    $outputPath = if ([System.IO.Path]::IsPathRooted($OutputFile)) {
        $OutputFile
    } else {
        Join-Path $script:scriptDir $OutputFile
    }

    Export-Results -Results $allResults -OutputPath $outputPath -Format $ExportFormat
}

# Mostrar estadísticas si se solicitó
if ($ShowStats) {
    $totalStats.Results = $allResults
    Show-Statistics -Stats $totalStats
}

Write-ColorOutput "`nBusqueda completada.`n" -Color $Colors.Success