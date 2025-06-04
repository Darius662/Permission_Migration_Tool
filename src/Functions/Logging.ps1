function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Create CSV entry
    $csvEntry = [PSCustomObject]@{
        Timestamp = $timestamp
        Level = $Level
        Message = $Message
    }
    
    if ($global:LogPath -and (Test-Path (Split-Path $global:LogPath))) {
        # Check if file exists and add header if needed
        if (-not (Test-Path $global:LogPath)) {
            $csvEntry | Export-Csv -Path $global:LogPath -NoTypeInformation
        } else {
            $csvEntry | Export-Csv -Path $global:LogPath -Append -NoTypeInformation
        }
    }
    
    Write-Host $logEntry -ForegroundColor $(
        switch ($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
    )
}
