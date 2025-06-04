function Test-RemoteComputer {
    param([string]$ComputerName)
    
    try {
        $result = Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction Stop
        return $result
    }
    catch {
        return $false
    }
}

function Get-RemoteLocalGroups {
    param([string]$ComputerName)
    
    try {
        Write-Log "Retrieving local groups from $ComputerName"
        $groups = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Get-LocalGroup | Select-Object Name, Description, SID
        } -ErrorAction Stop
        
        Write-Log "Retrieved $($groups.Count) groups from $ComputerName" -Level "SUCCESS"
        return $groups
    }
    catch {
        Write-Log "Failed to retrieve groups from $ComputerName`: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Copy-GroupsToTarget {
    param(
        [string]$SourcePC,
        [string]$TargetPC
    )
    
    try {
        $sourceGroups = Get-RemoteLocalGroups -ComputerName $SourcePC
        if (-not $sourceGroups) {
            Write-Log "No groups retrieved from source PC" -Level "ERROR"
            return $false
        }
        
        Write-Log "Copying groups to $TargetPC"
        
        Invoke-Command -ComputerName $TargetPC -ScriptBlock {
            param($Groups)
            
            foreach ($group in $Groups) {
                try {
                    $existingGroup = Get-LocalGroup -Name $group.Name -ErrorAction SilentlyContinue
                    
                    if (-not $existingGroup) {
                        New-LocalGroup -Name $group.Name -Description $group.Description
                        Write-Output "Created group: $($group.Name)"
                    }
                    else {
                        Write-Output "Group already exists: $($group.Name)"
                    }
                }
                catch {
                    Write-Output "Failed to create group $($group.Name): $($_.Exception.Message)"
                }
            }
        } -ArgumentList @(,$sourceGroups)
        
        Write-Log "Group copying completed" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to copy groups: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Remove-SelectedGroups {
    param(
        [string]$TargetPC,
        [array]$GroupsToRemove
    )
    
    if (-not $GroupsToRemove -or $GroupsToRemove.Count -eq 0) {
        Write-Log "No groups selected for removal" -Level "WARNING"
        return $true
    }
    
    try {
        Write-Log "Removing $($GroupsToRemove.Count) selected groups from $TargetPC"
        
        $result = Invoke-Command -ComputerName $TargetPC -ScriptBlock {
            param($Groups)
            
            $removedCount = 0
            $failedCount = 0
            
            foreach ($groupName in $Groups) {
                try {
                    $group = Get-LocalGroup -Name $groupName -ErrorAction SilentlyContinue
                    
                    if ($group) {
                        $protectedGroups = @("Administrators", "Users", "Guests", "Power Users", "Backup Operators", "Replicator")
                        
                        if ($groupName -in $protectedGroups) {
                            Write-Output "Skipped protected group: $groupName"
                            continue
                        }
                        
                        Remove-LocalGroup -Name $groupName -ErrorAction Stop
                        Write-Output "Removed group: $groupName"
                        $removedCount++
                    }
                    else {
                        Write-Output "Group not found: $groupName"
                    }
                }
                catch {
                    Write-Output "Failed to remove group $groupName`: $($_.Exception.Message)"
                    $failedCount++
                }
            }
            
            return @{
                RemovedCount = $removedCount
                FailedCount = $failedCount
            }
        } -ArgumentList @(,$GroupsToRemove)
        
        Write-Log "Group removal completed: $($result.RemovedCount) removed, $($result.FailedCount) failed" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to remove groups: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Backup-Permissions {
    param([string]$Path)
    
    try {
        $backupPath = Join-Path (Split-Path $global:LogPath) "permissions_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        Write-Log "Backing up current permissions to $backupPath"
        
        $backupContent = @()
        
        # Add header
        $backupContent += "# Permission Backup - $(Get-Date)"
        $backupContent += "# Source Path: $Path"
        $backupContent += "# Format: Path|Owner|AccessRule|IdentityReference|AccessControlType|Rights|IsInherited|InheritanceFlags|PropagationFlags"
        $backupContent += ""
        
        # Get permissions for each directory
        Get-ChildItem -Path $Path -Recurse -Directory | ForEach-Object {
            $acl = Get-Acl -Path $_.FullName
            
            # Add owner information
            $backupContent += "# Owner: $($acl.Owner)"
            $backupContent += "# Group: $($acl.Group)"
            
            # Add each access rule
            foreach ($rule in $acl.Access) {
                $backupContent += "$_|" + 
                                $acl.Owner + "|" +
                                $rule.IdentityReference + "|" +
                                $rule.AccessControlType + "|" +
                                $rule.FileSystemRights + "|" +
                                $rule.IsInherited + "|" +
                                $rule.InheritanceFlags + "|" +
                                $rule.PropagationFlags
            }
            
            $backupContent += ""
        }
        
        # Write to file
        $backupContent | Set-Content -Path $backupPath -Encoding UTF8
        Write-Log "Permissions backed up successfully to $backupPath" -Level "SUCCESS"
        return $backupPath
    }
    catch {
        Write-Log "Failed to backup permissions: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Apply-PermissionsFromSource {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [string]$SourcePC
    )
    
    try {
        Write-Log "Applying permissions from $SourcePath to $TargetPath"
        
        Invoke-Command -ComputerName $SourcePC -ScriptBlock {
            param($SourcePath, $TargetPath)
            
            $sourceAcl = Get-Acl -Path $SourcePath
            $targetAcl = Get-Acl -Path $TargetPath
            
            # Copy all access rules
            foreach ($rule in $sourceAcl.Access) {
                $targetAcl.AddAccessRule($rule)
            }
            
            # Copy owner
            $targetAcl.SetOwner($sourceAcl.Owner)
            
            # Copy group
            if ($sourceAcl.Group) {
                $targetAcl.SetGroup($sourceAcl.Group)
            }
            
            # Apply the modified ACL
            Set-Acl -Path $TargetPath -AclObject $targetAcl
            
            Write-Output "Permissions applied successfully"
        } -ArgumentList $SourcePath, $TargetPath
        
        Write-Log "Permissions applied successfully" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to apply permissions: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# New function to restore permissions from backup
function Restore-PermissionsFromBackup {
    param([string]$BackupPath, [string]$TargetPath)
    
    try {
        Write-Log "Restoring permissions from backup $BackupPath to $TargetPath"
        
        # Read the backup file
        $backupContent = Get-Content -Path $BackupPath
        $currentPath = $null
        $owner = $null
        $group = $null
        
        foreach ($line in $backupContent) {
            if ($line.StartsWith("#")) {
                # Header line
                if ($line -match "# Owner:") {
                    $owner = $line -replace "# Owner: ", ""
                }
                elseif ($line -match "# Group:") {
                    $group = $line -replace "# Group: ", ""
                }
                continue
            }
            
            if ($line -eq "") {
                # Empty line indicates end of current path's permissions
                continue
            }
            
            # Get the current path
            $currentPath = $line -split "\|"[0]
            
            # Skip if not in target path
            if (-not $currentPath.StartsWith($TargetPath)) {
                continue
            }
            
            # Get ACL for current path
            $acl = Get-Acl -Path $currentPath
            
            # Clear existing permissions
            $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }
            
            # Set owner and group
            if ($owner) {
                $acl.SetOwner($owner)
            }
            if ($group) {
                $acl.SetGroup($group)
            }
            
            # Add permissions from the backup
            foreach ($permLine in $backupContent) {
                if ($permLine -match "^$currentPath\|") {
                    $fields = $permLine -split "\|"
                    
                    # Skip header lines
                    if ($fields[0] -eq $currentPath) {
                        continue
                    }
                    
                    # Create and add the access rule
                    $identity = $fields[2]
                    $rights = $fields[4]
                    $type = $fields[3]
                    $inheritance = $fields[5]
                    $flags = $fields[6]
                    
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $identity,
                        $rights,
                        $inheritance,
                        $flags,
                        $type
                    )
                    
                    $acl.AddAccessRule($rule)
                }
            }
            
            # Apply the ACL
            Set-Acl -Path $currentPath -AclObject $acl
            
            # Reset for next path
            $owner = $null
            $group = $null
        }
        
        Write-Log "Permissions restored successfully" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to restore permissions: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# New function to compare permissions
function Compare-Permissions {
    param(
        [string]$Path1,
        [string]$Path2,
        [string]$ComputerName
    )
    
    try {
        Write-Log "Comparing permissions between $Path1 and $Path2"
        
        $acl1 = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($Path)
            Get-Acl -Path $Path
        } -ArgumentList $Path1
        
        $acl2 = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($Path)
            Get-Acl -Path $Path
        } -ArgumentList $Path2
        
        $differences = @{
            AccessRules = Compare-Object -ReferenceObject $acl1.Access -DifferenceObject $acl2.Access
            Owner = if ($acl1.Owner -ne $acl2.Owner) { $true } else { $false }
            Group = if ($acl1.Group -ne $acl2.Group) { $true } else { $false }
        }
        
        Write-Log "Permission comparison completed" -Level "SUCCESS"
        return $differences
    }
    catch {
        Write-Log "Failed to compare permissions: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}
