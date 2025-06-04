# Permission Migration Tool
# This script removes permissions, copies groups between PCs, and reapplies permissions
# Author: Claude AI Assistant
# Version: 1.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global variables
$global:LogPath = ""
$global:SourcePC = ""
$global:TargetPC = ""
$global:RootFolder = ""

# Import required modules
. (Join-Path $PSScriptRoot "src\Functions\Logging.ps1")
. (Join-Path $PSScriptRoot "src\Functions\PermissionManagement.ps1")
. (Join-Path $PSScriptRoot "src\Functions\Migration.ps1")
. (Join-Path $PSScriptRoot "src\GUI\Forms.ps1")

# Main execution
if ($Host.Name -eq "ConsoleHost") {
    Write-Host "Permission Migration Tool"
    Write-Host "Please run this script using PowerShell ISE or a GUI PowerShell host"
    exit
}

# Show main form
Show-MainForm

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    if ($global:LogPath -and (Test-Path (Split-Path $global:LogPath))) {
        Add-Content -Path $global:LogPath -Value $logEntry
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

# Function to test remote computer connectivity
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

# Function to get local groups from source PC
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

# Function to copy groups to target PC
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
                    # Check if group already exists
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

# Function to remove selected groups from target PC
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
                    # Check if group exists
                    $group = Get-LocalGroup -Name $groupName -ErrorAction SilentlyContinue
                    
                    if ($group) {
                        # Check if it's a built-in group that shouldn't be removed
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

# Function to backup current permissions
function Backup-Permissions {
    param([string]$Path)
    
    try {
        $backupPath = Join-Path (Split-Path $global:LogPath) "permissions_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml"
        Write-Log "Backing up current permissions to $backupPath"
        
        $permissions = @()
        Get-ChildItem -Path $Path -Recurse -Directory | ForEach-Object {
            $acl = Get-Acl -Path $_.FullName
            $permissions += [PSCustomObject]@{
                Path = $_.FullName
                Owner = $acl.Owner
                AccessRules = $acl.Access
            }
        }
        
        $permissions | Export-Clixml -Path $backupPath
        Write-Log "Permissions backed up successfully to $backupPath" -Level "SUCCESS"
        return $backupPath
    }
    catch {
        Write-Log "Failed to backup permissions: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

# Function to remove all permissions recursively
function Remove-AllPermissions {
    param([string]$Path)
    
    try {
        Write-Log "Removing all permissions from $Path and its children"
        $itemCount = 0
        
        Get-ChildItem -Path $Path -Recurse -Force | ForEach-Object {
            try {
                $acl = Get-Acl -Path $_.FullName
                
                # Remove all access rules except inherited ones
                $acl.Access | Where-Object { -not $_.IsInherited } | ForEach-Object {
                    $acl.RemoveAccessRule($_) | Out-Null
                }
                
                # Disable inheritance and remove inherited permissions
                $acl.SetAccessRuleProtection($true, $false)
                
                Set-Acl -Path $_.FullName -AclObject $acl
                $itemCount++
                
                if ($itemCount % 100 -eq 0) {
                    Write-Log "Processed $itemCount items..."
                }
            }
            catch {
                Write-Log "Failed to remove permissions from $($_.FullName): $($_.Exception.Message)" -Level "WARNING"
            }
        }
        
        Write-Log "Permissions removed from $itemCount items" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to remove permissions: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Function to apply permissions from source
function Apply-PermissionsFromSource {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [string]$SourcePC
    )
    
    try {
        Write-Log "Retrieving permissions from source: $SourcePath on $SourcePC"
        
        $sourcePermissions = Invoke-Command -ComputerName $SourcePC -ScriptBlock {
            param($Path)
            
            $permissions = @()
            if (Test-Path $Path) {
                Get-ChildItem -Path $Path -Recurse -Force | ForEach-Object {
                    $acl = Get-Acl -Path $_.FullName
                    $relativePath = $_.FullName.Replace($Path, "").TrimStart('\')
                    
                    $permissions += [PSCustomObject]@{
                        RelativePath = $relativePath
                        Owner = $acl.Owner
                        AccessRules = $acl.Access | Where-Object { -not $_.IsInherited }
                    }
                }
            }
            return $permissions
        } -ArgumentList $SourcePath
        
        Write-Log "Applying permissions to target path: $TargetPath"
        $appliedCount = 0
        
        foreach ($item in $sourcePermissions) {
            try {
                $targetItemPath = if ($item.RelativePath) {
                    Join-Path $TargetPath $item.RelativePath
                } else {
                    $TargetPath
                }
                
                if (Test-Path $targetItemPath) {
                    $acl = Get-Acl -Path $targetItemPath
                    
                    # Set owner
                    try {
                        $acl.SetOwner([System.Security.Principal.NTAccount]$item.Owner)
                    }
                    catch {
                        Write-Log "Could not set owner for $targetItemPath`: $($_.Exception.Message)" -Level "WARNING"
                    }
                    
                    # Add access rules
                    foreach ($rule in $item.AccessRules) {
                        try {
                            $acl.SetAccessRule($rule)
                        }
                        catch {
                            Write-Log "Could not apply access rule for $targetItemPath`: $($_.Exception.Message)" -Level "WARNING"
                        }
                    }
                    
                    Set-Acl -Path $targetItemPath -AclObject $acl
                    $appliedCount++
                    
                    if ($appliedCount % 50 -eq 0) {
                        Write-Log "Applied permissions to $appliedCount items..."
                    }
                }
            }
            catch {
                Write-Log "Failed to apply permissions to $targetItemPath`: $($_.Exception.Message)" -Level "WARNING"
            }
        }
        
        Write-Log "Permissions applied to $appliedCount items" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to apply permissions from source: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Group Management Form
function Show-GroupManagementForm {
    param([string]$TargetPC)
    
    # Get current groups from target PC
    Write-Log "Retrieving groups from $TargetPC for management"
    $targetGroups = Get-RemoteLocalGroups -ComputerName $TargetPC
    
    if (-not $targetGroups) {
        [System.Windows.Forms.MessageBox]::Show("Failed to retrieve groups from $TargetPC", "Error", "OK", "Error")
        return @()
    }
    
    # Create group management form
    $groupForm = New-Object System.Windows.Forms.Form
    $groupForm.Text = "Group Management - $TargetPC"
    $groupForm.Size = New-Object System.Drawing.Size(600, 500)
    $groupForm.StartPosition = "CenterScreen"
    $groupForm.MaximizeBox = $false
    
    # Instructions
    $lblInstructions = New-Object System.Windows.Forms.Label
    $lblInstructions.Text = "Select groups to REMOVE from $TargetPC (protected system groups will be skipped):"
    $lblInstructions.Location = New-Object System.Drawing.Point(20, 10)
    $lblInstructions.Size = New-Object System.Drawing.Size(550, 30)
    $groupForm.Controls.Add($lblInstructions)
    
    # Group list with checkboxes
    $groupListBox = New-Object System.Windows.Forms.CheckedListBox
    $groupListBox.Location = New-Object System.Drawing.Point(20, 50)
    $groupListBox.Size = New-Object System.Drawing.Size(540, 300)
    $groupListBox.CheckOnClick = $true
    
    # Add groups to list
    $protectedGroups = @("Administrators", "Users", "Guests", "Power Users", "Backup Operators", "Replicator")
    foreach ($group in $targetGroups | Sort-Object Name) {
        $displayText = if ($group.Name -in $protectedGroups) {
            "$($group.Name) - [PROTECTED] - $($group.Description)"
        } else {
            "$($group.Name) - $($group.Description)"
        }
        
        $index = $groupListBox.Items.Add($displayText)
        
        # Disable protected groups
        if ($group.Name -in $protectedGroups) {
            $groupListBox.SetItemCheckState($index, [System.Windows.Forms.CheckState]::Indeterminate)
        }
    }
    
    $groupForm.Controls.Add($groupListBox)
    
    # Selection buttons
    $btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = "Select All (Non-Protected)"
    $btnSelectAll.Location = New-Object System.Drawing.Point(20, 360)
    $btnSelectAll.Size = New-Object System.Drawing.Size(150, 30)
    $groupForm.Controls.Add($btnSelectAll)
    
    $btnSelectNone = New-Object System.Windows.Forms.Button
    $btnSelectNone.Text = "Select None"
    $btnSelectNone.Location = New-Object System.Drawing.Point(180, 360)
    $btnSelectNone.Size = New-Object System.Drawing.Size(100, 30)
    $groupForm.Controls.Add($btnSelectNone)
    
    # Action buttons
    $btnRemoveSelected = New-Object System.Windows.Forms.Button
    $btnRemoveSelected.Text = "Remove Selected"
    $btnRemoveSelected.Location = New-Object System.Drawing.Point(350, 360)
    $btnRemoveSelected.Size = New-Object System.Drawing.Size(120, 30)
    $btnRemoveSelected.BackColor = [System.Drawing.Color]::LightCoral
    $groupForm.Controls.Add($btnRemoveSelected)
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(480, 360)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 30)
    $groupForm.Controls.Add($btnCancel)
    
    # Selected groups label
    $lblSelected = New-Object System.Windows.Forms.Label
    $lblSelected.Text = "Selected: 0 groups"
    $lblSelected.Location = New-Object System.Drawing.Point(20, 400)
    $lblSelected.Size = New-Object System.Drawing.Size(200, 20)
    $groupForm.Controls.Add($lblSelected)
    
    # Update selected count
    $updateSelectedCount = {
        $selectedCount = 0
        for ($i = 0; $i -lt $groupListBox.Items.Count; $i++) {
            if ($groupListBox.GetItemCheckState($i) -eq [System.Windows.Forms.CheckState]::Checked) {
                $selectedCount++
            }
        }
        $lblSelected.Text = "Selected: $selectedCount groups"
    }
    
    # Event handlers
    $groupListBox.Add_ItemCheck({
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 1
        $timer.Add_Tick({
            $timer.Stop()
            $timer.Dispose()
            & $updateSelectedCount
        })
        $timer.Start()
    })
    
    $btnSelectAll.Add_Click({
        for ($i = 0; $i -lt $groupListBox.Items.Count; $i++) {
            if ($groupListBox.GetItemCheckState($i) -ne [System.Windows.Forms.CheckState]::Indeterminate) {
                $groupListBox.SetItemChecked($i, $true)
            }
        }
        & $updateSelectedCount
    })
    
    $btnSelectNone.Add_Click({
        for ($i = 0; $i -lt $groupListBox.Items.Count; $i++) {
            if ($groupListBox.GetItemCheckState($i) -ne [System.Windows.Forms.CheckState]::Indeterminate) {
                $groupListBox.SetItemChecked($i, $false)
            }
        }
        & $updateSelectedCount
    })
    
    $selectedGroups = @()
    
    $btnRemoveSelected.Add_Click({
        $selectedGroups = @()
        
        for ($i = 0; $i -lt $groupListBox.Items.Count; $i++) {
            if ($groupListBox.GetItemChecked($i)) {
                $groupName = ($targetGroups[$i]).Name
                $selectedGroups += $groupName
            }
        }
        
        if ($selectedGroups.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No groups selected for removal.", "Information", "OK", "Information")
            return
        }
        
        $confirmMessage = "Are you sure you want to remove the following $($selectedGroups.Count) groups from $TargetPC`?`n`n" + ($selectedGroups -join "`n")
        $result = [System.Windows.Forms.MessageBox]::Show($confirmMessage, "Confirm Group Removal", "YesNo", "Warning")
        
        if ($result -eq "Yes") {
            $groupForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $groupForm.Tag = $selectedGroups
            $groupForm.Close()
        }
    })
    
    $btnCancel.Add_Click({
        $groupForm.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $groupForm.Close()
    })
    
    # Initial count update
    & $updateSelectedCount
    
    # Show form and return selected groups
    $dialogResult = $groupForm.ShowDialog()
    
    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        return $groupForm.Tag
    } else {
        return @()
    }
}
function Start-PermissionMigration {
    param(
        [string]$SourcePC,
        [string]$TargetPC,
        [string]$RootFolder,
        [string]$SourceFolder
    )
    
    Write-Log "=== Starting Permission Migration Process ===" -Level "SUCCESS"
    Write-Log "Source PC: $SourcePC"
    Write-Log "Target PC: $TargetPC"
    Write-Log "Root Folder: $RootFolder"
    Write-Log "Source Folder: $SourceFolder"
    
    # Test connectivity
    Write-Log "Testing connectivity to source PC..."
    if (-not (Test-RemoteComputer -ComputerName $SourcePC)) {
        Write-Log "Cannot connect to source PC: $SourcePC" -Level "ERROR"
        return $false
    }
    
    Write-Log "Testing connectivity to target PC..."
    if (-not (Test-RemoteComputer -ComputerName $TargetPC)) {
        Write-Log "Cannot connect to target PC: $TargetPC" -Level "ERROR"
        return $false
    }
    
    # Backup current permissions
    $backupPath = Backup-Permissions -Path $RootFolder
    if (-not $backupPath) {
        Write-Log "Permission backup failed. Continuing anyway..." -Level "WARNING"
    }
    
    # Copy groups from source to target
    Write-Log "Step 1: Copying groups from source to target PC..."
    if (-not (Copy-GroupsToTarget -SourcePC $SourcePC -TargetPC $TargetPC)) {
        Write-Log "Group copying failed" -Level "ERROR"
        return $false
    }
    
    # Remove existing permissions
    Write-Log "Step 2: Removing existing permissions..."
    if (-not (Remove-AllPermissions -Path $RootFolder)) {
        Write-Log "Permission removal failed" -Level "ERROR"
        return $false
    }
    
    # Apply permissions from source
    Write-Log "Step 3: Applying permissions from source..."
    if (-not (Apply-PermissionsFromSource -SourcePath $SourceFolder -TargetPath $RootFolder -SourcePC $SourcePC)) {
        Write-Log "Permission application failed" -Level "ERROR"
        return $false
    }
    
    Write-Log "=== Permission Migration Completed Successfully ===" -Level "SUCCESS"
    return $true
}

# Create the main form
function Show-MainForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Permission Migration Tool"
    $form.Size = New-Object System.Drawing.Size(600, 500)
    $form.StartPosition = "CenterScreen"
    $form.MaximizeBox = $false
    
    # Source PC
    $lblSourcePC = New-Object System.Windows.Forms.Label
    $lblSourcePC.Text = "Source PC (PC1):"
    $lblSourcePC.Location = New-Object System.Drawing.Point(20, 20)
    $lblSourcePC.Size = New-Object System.Drawing.Size(100, 20)
    $form.Controls.Add($lblSourcePC)
    
    $txtSourcePC = New-Object System.Windows.Forms.TextBox
    $txtSourcePC.Location = New-Object System.Drawing.Point(130, 18)
    $txtSourcePC.Size = New-Object System.Drawing.Size(200, 20)
    $form.Controls.Add($txtSourcePC)
    
    # Target PC
    $lblTargetPC = New-Object System.Windows.Forms.Label
    $lblTargetPC.Text = "Target PC (PC2):"
    $lblTargetPC.Location = New-Object System.Drawing.Point(20, 50)
    $lblTargetPC.Size = New-Object System.Drawing.Size(100, 20)
    $form.Controls.Add($lblTargetPC)
    
    $txtTargetPC = New-Object System.Windows.Forms.TextBox
    $txtTargetPC.Location = New-Object System.Drawing.Point(130, 48)
    $txtTargetPC.Size = New-Object System.Drawing.Size(200, 20)
    $form.Controls.Add($txtTargetPC)
    
    # Source folder path
    $lblSourceFolder = New-Object System.Windows.Forms.Label
    $lblSourceFolder.Text = "Source Folder (on PC1):"
    $lblSourceFolder.Location = New-Object System.Drawing.Point(20, 80)
    $lblSourceFolder.Size = New-Object System.Drawing.Size(130, 20)
    $form.Controls.Add($lblSourceFolder)
    
    $txtSourceFolder = New-Object System.Windows.Forms.TextBox
    $txtSourceFolder.Location = New-Object System.Drawing.Point(155, 78)
    $txtSourceFolder.Size = New-Object System.Drawing.Size(300, 20)
    $form.Controls.Add($txtSourceFolder)
    
    $btnBrowseSource = New-Object System.Windows.Forms.Button
    $btnBrowseSource.Text = "Browse"
    $btnBrowseSource.Location = New-Object System.Drawing.Point(465, 76)
    $btnBrowseSource.Size = New-Object System.Drawing.Size(75, 25)
    $form.Controls.Add($btnBrowseSource)
    
    # Target folder path
    $lblTargetFolder = New-Object System.Windows.Forms.Label
    $lblTargetFolder.Text = "Target Folder (on PC2):"
    $lblTargetFolder.Location = New-Object System.Drawing.Point(20, 110)
    $lblTargetFolder.Size = New-Object System.Drawing.Size(130, 20)
    $form.Controls.Add($lblTargetFolder)
    
    $txtTargetFolder = New-Object System.Windows.Forms.TextBox
    $txtTargetFolder.Location = New-Object System.Drawing.Point(155, 108)
    $txtTargetFolder.Size = New-Object System.Drawing.Size(300, 20)
    $form.Controls.Add($txtTargetFolder)
    
    $btnBrowseTarget = New-Object System.Windows.Forms.Button
    $btnBrowseTarget.Text = "Browse"
    $btnBrowseTarget.Location = New-Object System.Drawing.Point(465, 106)
    $btnBrowseTarget.Size = New-Object System.Drawing.Size(75, 25)
    $form.Controls.Add($btnBrowseTarget)
    
    # Log file path
    $lblLogPath = New-Object System.Windows.Forms.Label
    $lblLogPath.Text = "Log File Path:"
    $lblLogPath.Location = New-Object System.Drawing.Point(20, 140)
    $lblLogPath.Size = New-Object System.Drawing.Size(80, 20)
    $form.Controls.Add($lblLogPath)
    
    $txtLogPath = New-Object System.Windows.Forms.TextBox
    $txtLogPath.Location = New-Object System.Drawing.Point(105, 138)
    $txtLogPath.Size = New-Object System.Drawing.Size(350, 20)
    $form.Controls.Add($txtLogPath)
    
    $btnBrowseLog = New-Object System.Windows.Forms.Button
    $btnBrowseLog.Text = "Browse"
    $btnBrowseLog.Location = New-Object System.Drawing.Point(465, 136)
    $btnBrowseLog.Size = New-Object System.Drawing.Size(75, 25)
    $form.Controls.Add($btnBrowseLog)
    
    # Progress bar
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(20, 180)
    $progressBar.Size = New-Object System.Drawing.Size(520, 20)
    $progressBar.Style = "Marquee"
    $progressBar.MarqueeAnimationSpeed = 0
    $form.Controls.Add($progressBar)
    
    # Log output
    $lblOutput = New-Object System.Windows.Forms.Label
    $lblOutput.Text = "Log Output:"
    $lblOutput.Location = New-Object System.Drawing.Point(20, 210)
    $lblOutput.Size = New-Object System.Drawing.Size(80, 20)
    $form.Controls.Add($lblOutput)
    
    $txtOutput = New-Object System.Windows.Forms.TextBox
    $txtOutput.Location = New-Object System.Drawing.Point(20, 230)
    $txtOutput.Size = New-Object System.Drawing.Size(520, 180)
    $txtOutput.Multiline = $true
    $txtOutput.ScrollBars = "Vertical"
    $txtOutput.ReadOnly = $true
    $form.Controls.Add($txtOutput)
    
    # Manage Groups button
    $btnManageGroups = New-Object System.Windows.Forms.Button
    $btnManageGroups.Text = "Manage Groups"
    $btnManageGroups.Location = New-Object System.Drawing.Point(240, 420)
    $btnManageGroups.Size = New-Object System.Drawing.Size(100, 30)
    $btnManageGroups.BackColor = [System.Drawing.Color]::LightBlue
    $form.Controls.Add($btnManageGroups)
    
    # Buttons
    $btnStart = New-Object System.Windows.Forms.Button
    $btnStart.Text = "Start Migration"
    $btnStart.Location = New-Object System.Drawing.Point(350, 420)
    $btnStart.Size = New-Object System.Drawing.Size(100, 30)
    $btnStart.BackColor = [System.Drawing.Color]::LightGreen
    $form.Controls.Add($btnStart)
    
    $btnExit = New-Object System.Windows.Forms.Button
    $btnExit.Text = "Exit"
    $btnExit.Location = New-Object System.Drawing.Point(460, 420)
    $btnExit.Size = New-Object System.Drawing.Size(80, 30)
    $form.Controls.Add($btnExit)
    
    # Event handlers
    $btnBrowseSource.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = "Select source folder"
        if ($folderDialog.ShowDialog() -eq "OK") {
            $txtSourceFolder.Text = $folderDialog.SelectedPath
        }
    })
    
    $btnBrowseTarget.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = "Select target folder"
        if ($folderDialog.ShowDialog() -eq "OK") {
            $txtTargetFolder.Text = $folderDialog.SelectedPath
        }
    })
    
    $btnBrowseLog.Add_Click({
        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveDialog.Filter = "Log files (*.log)|*.log|Text files (*.txt)|*.txt|All files (*.*)|*.*"
        $saveDialog.DefaultExt = "log"
        if ($saveDialog.ShowDialog() -eq "OK") {
            $txtLogPath.Text = $saveDialog.FileName
        }
    })
    
    $btnManageGroups.Add_Click({
        if (-not $txtTargetPC.Text) {
            [System.Windows.Forms.MessageBox]::Show("Please enter the Target PC name first.", "Validation Error", "OK", "Warning")
            return
        }
        
        # Test connectivity to target PC
        if (-not (Test-RemoteComputer -ComputerName $txtTargetPC.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Cannot connect to target PC: $($txtTargetPC.Text). Please check the computer name and network connectivity.", "Connection Error", "OK", "Error")
            return
        }
        
        # Set up temporary logging for group management
        if ($txtLogPath.Text) {
            $global:LogPath = $txtLogPath.Text
        }
        
        # Show group management form
        $groupsToRemove = Show-GroupManagementForm -TargetPC $txtTargetPC.Text
        
        if ($groupsToRemove -and $groupsToRemove.Count -gt 0) {
            try {
                $progressBar.MarqueeAnimationSpeed = 30
                $btnManageGroups.Enabled = $false
                
                # Clear output and add header
                $txtOutput.Clear()
                $txtOutput.AppendText("=== Group Management Started ===`r`n")
                $txtOutput.ScrollToCaret()
                $form.Refresh()
                
                # Custom Write-Log for GUI updates
                $originalWriteLog = ${function:Write-Log}
                ${function:Write-Log} = {
                    param([string]$Message, [string]$Level = "INFO")
                    
                    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    $logEntry = "[$timestamp] [$Level] $Message"
                    
                    if ($global:LogPath -and (Test-Path (Split-Path $global:LogPath))) {
                        Add-Content -Path $global:LogPath -Value $logEntry
                    }
                    
                    $txtOutput.AppendText("$logEntry`r`n")
                    $txtOutput.ScrollToCaret()
                    $form.Refresh()
                }
                
                $success = Remove-SelectedGroups -TargetPC $txtTargetPC.Text -GroupsToRemove $groupsToRemove
                
                if ($success) {
                    [System.Windows.Forms.MessageBox]::Show("Selected groups have been removed successfully!", "Success", "OK", "Information")
                } else {
                    [System.Windows.Forms.MessageBox]::Show("Group removal completed with some errors. Check the log for details.", "Warning", "OK", "Warning")
                }
            }
            finally {
                ${function:Write-Log} = $originalWriteLog
                $progressBar.MarqueeAnimationSpeed = 0
                $btnManageGroups.Enabled = $true
            }
        }
    })
    
    $btnStart.Add_Click({
        # Validate inputs
        if (-not $txtSourcePC.Text -or -not $txtTargetPC.Text -or -not $txtSourceFolder.Text -or -not $txtTargetFolder.Text -or -not $txtLogPath.Text) {
            [System.Windows.Forms.MessageBox]::Show("Please fill in all fields.", "Validation Error", "OK", "Warning")
            return
        }
        
        # Set global variables
        $global:LogPath = $txtLogPath.Text
        
        # Clear output and start progress
        $txtOutput.Clear()
        $progressBar.MarqueeAnimationSpeed = 30
        $btnStart.Enabled = $false
        
        # Custom Write-Log for GUI updates
        $originalWriteLog = ${function:Write-Log}
        ${function:Write-Log} = {
            param([string]$Message, [string]$Level = "INFO")
            
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $logEntry = "[$timestamp] [$Level] $Message"
            
            if ($global:LogPath -and (Test-Path (Split-Path $global:LogPath))) {
                Add-Content -Path $global:LogPath -Value $logEntry
            }
            
            $txtOutput.AppendText("$logEntry`r`n")
            $txtOutput.ScrollToCaret()
            $form.Refresh()
        }
        
        try {
            $result = Start-PermissionMigration -SourcePC $txtSourcePC.Text -TargetPC $txtTargetPC.Text -RootFolder $txtTargetFolder.Text -SourceFolder $txtSourceFolder.Text
            
            if ($result) {
                [System.Windows.Forms.MessageBox]::Show("Permission migration completed successfully!", "Success", "OK", "Information")
            } else {
                [System.Windows.Forms.MessageBox]::Show("Permission migration failed. Check the log for details.", "Error", "OK", "Error")
            }
        }
        finally {
            # Restore Write-Log and stop progress
            ${function:Write-Log} = $originalWriteLog
            $progressBar.MarqueeAnimationSpeed = 0
            $btnStart.Enabled = $true
        }
    })
    
    $btnExit.Add_Click({
        $form.Close()
    })
    
    # Show the form
    $form.ShowDialog()
}

# Main execution
if ($Host.Name -eq "ConsoleHost") {
    Write-Host "Permission Migration Tool"
    Write-Host "========================"
    Write-Host "Starting GUI..."
    Show-MainForm
}