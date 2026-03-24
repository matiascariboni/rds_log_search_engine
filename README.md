# RDS Log Search Engine

PowerShell script for advanced search in Amazon RDS audit logs.

## 📋 Features

- ✅ Simultaneous search in multiple log files
- ✅ Support for prod and preprod environments
- ✅ Multiple term search (AND/OR logical)
- ✅ Advanced filters (date, application, database, action)
- ✅ Export to CSV, JSON or TXT
- ✅ Detailed search statistics
- ✅ Interactive mode for less technical users
- ✅ Colors and improved console formatting
- ✅ Configurable result limit
- ✅ Visual progress during long searches

## 📁 Required Directory Structure

```
log_search_engine/
├── Search-RDSLogs.ps1          # Main script
├── prod/
│   ├── server_audit.log
│   ├── server_audit.log.01
│   ├── server_audit.log.02
│   └── ...
└── preprod/
    ├── server_audit.log
    ├── server_audit.log.01
    ├── server_audit.log.02
    └── ...
```

## 🚀 Installation

1. Copy the `Search-RDSLogs.ps1` script to the root folder `log_search_engine`
2. Ensure the `prod` and `preprod` folders contain the logs
3. Run PowerShell as administrator (if necessary)

## 🎯 Basic Usage

### Interactive Mode (Recommended for beginners)

```powershell
.\Search-RDSLogs.ps1 -Interactive
```

The script will guide you step by step through all options.

### Quick Searches

**Search for a term in production:**
```powershell
.\Search-RDSLogs.ps1 -Environment prod -SearchTerms "mqtt-decoder"
```

**Search in both environments:**
```powershell
.\Search-RDSLogs.ps1 -Environment both -SearchTerms "ERROR"
```

**Search for a specific GlobalSmartID:**
```powershell
.\Search-RDSLogs.ps1 -Environment prod -SearchTerms "HGQ09NJ0N94"
```

### Multiple Term Searches

**Search for lines with ANY term (OR logic):**
```powershell
.\Search-RDSLogs.ps1 -Environment both -SearchTerms "ERROR","FAIL","TIMEOUT"
```

**Search for lines with ALL terms (AND logic):**
```powershell
.\Search-RDSLogs.ps1 -Environment prod -SearchTerms "mqtt-decoder","INSERT" -MatchAll
```

### Advanced Filters

**Filter by application:**
```powershell
.\Search-RDSLogs.ps1 -Environment prod -Application "mqtt-decoder" -ShowStats
```

**Filter by database:**
```powershell
.\Search-RDSLogs.ps1 -Environment preprod -Database "ENV000_MasterCommonData"
```

**Filter by action type:**
```powershell
.\Search-RDSLogs.ps1 -Environment prod -Action "QUERY"
```

**Filter by date range:**
```powershell
.\Search-RDSLogs.ps1 -Environment both -DateFrom "2025-12-16" -DateTo "2025-12-16 12:00:00"
```

**Combinación de filtros:**
```powershell
.\Search-RDSLogs.ps1 `
    -Environment prod `
    -Application "mqtt-decoder" `
    -Action "INSERT" `
    -DateFrom "2025-12-16 10:00:00" `
    -DateTo "2025-12-16 12:00:00" `
    -ShowStats
```

### Exportación de Resultados

**Exportar a CSV:**
```powershell
.\Search-RDSLogs.ps1 -Environment prod -SearchTerms "ERROR" -OutputFile "errores.csv"
```

**Exportar a JSON:**
```powershell
.\Search-RDSLogs.ps1 -Environment both -Application "mqtt-decoder" `
    -OutputFile "mqtt_logs.json" -ExportFormat JSON
```

**Exportar a TXT (líneas originales):**
```powershell
.\Search-RDSLogs.ps1 -Environment prod -SearchTerms "HGQ09NJ0N94" `
    -OutputFile "device_logs.txt" -ExportFormat TXT
```

### Limitar Resultados

**Obtener solo los primeros 100 resultados:**
```powershell
.\Search-RDSLogs.ps1 -Environment prod -Action "QUERY" -MaxResults 100
```

### Búsqueda Sensible a Mayúsculas

```powershell
.\Search-RDSLogs.ps1 -Environment prod -SearchTerms "ERROR" -CaseSensitive
```

## 📊 Ejemplos de Uso Real

### 1. Investigar errores en las últimas 24 horas

```powershell
.\Search-RDSLogs.ps1 `
    -Environment both `
    -SearchTerms "error","fail","exception" `
    -DateFrom "2025-12-15" `
    -OutputFile "errores_recientes.csv" `
    -ShowStats
```

### 2. Analizar actividad de un dispositivo específico

```powershell
.\Search-RDSLogs.ps1 `
    -Environment prod `
    -SearchTerms "HGQ09NJ0N94:3" `
    -ShowStats `
    -OutputFile "dispositivo_HGQ09NJ0N94.csv"
```

### 3. Auditar queries en una base de datos

```powershell
.\Search-RDSLogs.ps1 `
    -Environment prod `
    -Database "ENV000_MasterCommonData" `
    -Action "QUERY" `
    -DateFrom "2025-12-16" `
    -MaxResults 1000 `
    -OutputFile "queries_mastercommon.csv"
```

### 4. Buscar todas las conexiones/desconexiones

```powershell
# Conexiones
.\Search-RDSLogs.ps1 -Environment prod -Action "CONNECT" -ShowStats

# Desconexiones
.\Search-RDSLogs.ps1 -Environment prod -Action "DISCONNECT" -ShowStats
```

### 5. Analizar actividad de mqtt-decoder

```powershell
.\Search-RDSLogs.ps1 `
    -Environment prod `
    -Application "mqtt-decoder" `
    -DateFrom "2025-12-16 11:00:00" `
    -DateTo "2025-12-16 12:00:00" `
    -ShowStats `
    -OutputFile "mqtt_decoder_analysis.csv"
```

### 6. Buscar inserciones con JSON específico

```powershell
.\Search-RDSLogs.ps1 `
    -Environment prod `
    -SearchTerms "tbl_AA_JSON_import","SDM630CT" `
    -MatchAll `
    -MaxResults 50
```

### 7. Encontrar stored procedures ejecutadas

```powershell
.\Search-RDSLogs.ps1 `
    -Environment both `
    -SearchTerms "CALL prc_" `
    -ShowStats `
    -OutputFile "stored_procedures.csv"
```

### 8. Búsqueda de patrones de sensor específico

```powershell
.\Search-RDSLogs.ps1 `
    -Environment prod `
    -SearchTerms "Eastron","SDM630CT" `
    -MatchAll `
    -DateFrom "2025-12-16" `
    -ShowStats
```

## 📝 Parámetros Disponibles

| Parámetro | Tipo | Valores | Descripción |
|-----------|------|---------|-------------|
| `-Environment` | String | prod, preprod, both | Ambiente donde buscar |
| `-SearchTerms` | String[] | Cualquier texto | Términos a buscar |
| `-MatchAll` | Switch | - | Buscar TODOS los términos (AND) |
| `-CaseSensitive` | Switch | - | Búsqueda sensible a mayúsculas |
| `-DateFrom` | String | yyyy-MM-dd [HH:mm:ss] | Fecha inicial |
| `-DateTo` | String | yyyy-MM-dd [HH:mm:ss] | Fecha final |
| `-Application` | String | Nombre de app | Filtrar por aplicación |
| `-Database` | String | Nombre de BD | Filtrar por base de datos |
| `-Action` | String | QUERY, CONNECT, etc. | Filtrar por acción |
| `-OutputFile` | String | Ruta de archivo | Archivo de salida |
| `-MaxResults` | Int | Número | Límite de resultados (0=sin límite) |
| `-ShowStats` | Switch | - | Mostrar estadísticas |
| `-ExportFormat` | String | CSV, JSON, TXT | Formato de exportación |
| `-Interactive` | Switch | - | Modo interactivo |

## 🎨 Salida del Script

El script muestra:

1. **Banner inicial** con información del script
2. **Criterios de búsqueda** aplicados
3. **Progreso** durante el procesamiento
4. **Resultados** encontrados (primeros 10 por defecto)
5. **Estadísticas** (si se solicita):
   - Total de líneas procesadas
   - Líneas que coinciden
   - Porcentaje de coincidencia
   - Top aplicaciones
   - Top acciones

## 🔧 Solución de Problemas

### Error: "No se pueden ejecutar scripts en este sistema"

Ejecuta en PowerShell como administrador:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### No encuentra los logs

Verifica que:
1. Estás ejecutando el script desde la carpeta `log_search_engine`
2. Existen las carpetas `prod` y `preprod`
3. Los archivos se llaman `server_audit.log` o `server_audit.log.XX`

### Búsqueda muy lenta

- Usa `-MaxResults` para limitar resultados
- Aplica filtros de fecha para reducir el rango
- Considera buscar solo en un ambiente a la vez

### Caracteres extraños en la salida

Asegúrate de que tu terminal soporte UTF-8. En PowerShell:
```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
```

## 💡 Tips y Mejores Prácticas

1. **Usa el modo interactivo** cuando no estés seguro de los parámetros
2. **Exporta resultados grandes** a CSV en lugar de mostrarlos en consola
3. **Aplica filtros de fecha** para búsquedas más rápidas
4. **Usa `-ShowStats`** para entender el volumen de datos
5. **Combina filtros** para búsquedas más precisas
6. **Guarda tus búsquedas frecuentes** como scripts .bat o .ps1

## 📚 Ejemplos de Scripts Reutilizables

### buscar_errores_hoy.bat
```batch
@echo off
powershell -ExecutionPolicy Bypass -File ".\Search-RDSLogs.ps1" ^
    -Environment both ^
    -SearchTerms "error","fail" ^
    -DateFrom "%date:~6,4%-%date:~3,2%-%date:~0,2%" ^
    -OutputFile "errores_%date:~0,2%%date:~3,2%%date:~6,4%.csv" ^
    -ShowStats
pause
```

### analizar_mqtt.bat
```batch
@echo off
powershell -ExecutionPolicy Bypass -File ".\Search-RDSLogs.ps1" ^
    -Environment prod ^
    -Application "mqtt-decoder" ^
    -ShowStats ^
    -MaxResults 500
pause
```

## 🆘 Soporte

Si encuentras problemas o tienes sugerencias:

1. Verifica que tu versión de PowerShell sea 5.1 o superior: `$PSVersionTable.PSVersion`
2. Revisa los logs para errores específicos
3. Intenta con búsquedas más simples primero
4. Usa el modo interactivo para validar tus criterios

## 📄 Licencia

Uso interno - Script de utilidad para análisis de logs de RDS.

---

**Versión:** 1.0  
**Última actualización:** Diciembre 2025  
**Compatibilidad:** PowerShell 5.1+
