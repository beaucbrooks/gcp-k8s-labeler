function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO",
        [string]$LogFile = "$PSScriptRoot\gke_cluster_export_$(Get-Date -Format 'yyyyMMdd').log", 
        [switch]$Verbose
    )
    
    # Define log levels with numeric priority
    $logLevels = @{
        "DEBUG" = 1
        "INFO"  = 2
        "WARN"  = 3
        "ERROR" = 4
    }

    # Ensure log level is valid
    if (-not $logLevels.ContainsKey($Level)) {
        Write-Error "Invalid log level: $Level. Use one of 'DEBUG', 'INFO', 'WARN', 'ERROR'."
        return
    }

    # Timestamp for logs
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # Create the log message
    $logMessage = "$timestamp|$Level|$Message"

    # Check log level for verbosity
    if ($logLevels[$Level] -ge $logLevels['INFO'] -or $Verbose) {
        Write-Host $logMessage
    }

    # Log to file
    if (Test-Path $LogFile) {
        $logSize = (Get-Item $LogFile).Length
        $maxSize = 10MB  # 10 MB limit before rotation

        # Rotate logs if size exceeds limit
        if ($logSize -gt $maxSize) {
            $timestampForFile = Get-Date -Format 'yyyyMMdd_HHmmss'
            $backupFile = "$LogFile.$timestampForFile"
            Rename-Item $LogFile -NewName $backupFile
            Write-Host "Log file exceeded $maxSize. Rotation occurred. Backup created as $backupFile."
        }
    }

    # Append log message to file
    Add-Content -Path $LogFile -Value $logMessage

    # Handle error level logs
    if ($Level -eq "ERROR") {
        Write-Error $Message
    }
}
