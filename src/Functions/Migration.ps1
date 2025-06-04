function Start-PermissionMigration {
    param(
        [string]$SourcePC,
        [string]$TargetPC,
        [string]$SourcePath,
        [string]$TargetPath
    )
    
    try {
        Write-Log "Starting permission migration from $SourcePC to $TargetPC"
        
        # Test connections
        if (-not (Test-RemoteComputer -ComputerName $SourcePC)) {
            Write-Log "Source PC $SourcePC is not accessible" -Level "ERROR"
            return $false
        }
        
        if (-not (Test-RemoteComputer -ComputerName $TargetPC)) {
            Write-Log "Target PC $TargetPC is not accessible" -Level "ERROR"
            return $false
        }
        
        # Backup permissions
        Write-Log "Creating backup of target permissions"
        $backupPath = Backup-Permissions -Path $TargetPath
        if (-not $backupPath) {
            Write-Log "Failed to create permissions backup" -Level "ERROR"
            return $false
        }
        
        # Copy groups
        Write-Log "Copying groups from $SourcePC to $TargetPC"
        if (-not (Copy-GroupsToTarget -SourcePC $SourcePC -TargetPC $TargetPC)) {
            Write-Log "Failed to copy groups" -Level "ERROR"
            return $false
        }
        
        # Apply permissions
        Write-Log "Applying permissions from $SourcePath to $TargetPath"
        if (-not (Apply-PermissionsFromSource -SourcePath $SourcePath -TargetPath $TargetPath -SourcePC $SourcePC)) {
            Write-Log "Failed to apply permissions" -Level "ERROR"
            return $false
        }
        
        Write-Log "Permission migration completed successfully" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Migration failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}
