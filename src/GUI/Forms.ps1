function Show-GroupManagementForm {
    param([string]$TargetPC)
    
    # Get current groups from target PC
    Write-Log "Retrieving groups from $TargetPC for management"
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Group Management - $TargetPC"
    $form.Size = New-Object System.Drawing.Size(800, 600)
    $form.StartPosition = "CenterScreen"
    
    # Create checked list box for groups
    $groupListBox = New-Object System.Windows.Forms.CheckedListBox
    $groupListBox.Location = New-Object System.Drawing.Point(20, 20)
    $groupListBox.Size = New-Object System.Drawing.Size(740, 400)
    
    try {
        $groups = Get-RemoteLocalGroups -ComputerName $TargetPC
        if ($groups) {
            foreach ($group in $groups) {
                $groupListBox.Items.Add($group.Name)
            }
        }
    }
    catch {
        Write-Log "Failed to load groups: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Failed to load groups from $TargetPC", "Error", "OK", "Error")
        return
    }
    
    # Create buttons
    $btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = "Select All"
    $btnSelectAll.Location = New-Object System.Drawing.Point(20, 440)
    $btnSelectAll.Size = New-Object System.Drawing.Size(100, 30)
    $btnSelectAll.Add_Click({
        for ($i = 0; $i -lt $groupListBox.Items.Count; $i++) {
            $groupListBox.SetItemChecked($i, $true)
        }
    })
    
    $btnSelectNone = New-Object System.Windows.Forms.Button
    $btnSelectNone.Text = "Select None"
    $btnSelectNone.Location = New-Object System.Drawing.Point(140, 440)
    $btnSelectNone.Size = New-Object System.Drawing.Size(100, 30)
    $btnSelectNone.Add_Click({
        for ($i = 0; $i -lt $groupListBox.Items.Count; $i++) {
            $groupListBox.SetItemChecked($i, $false)
        }
    })
    
    $btnRemoveSelected = New-Object System.Windows.Forms.Button
    $btnRemoveSelected.Text = "Remove Selected"
    $btnRemoveSelected.Location = New-Object System.Drawing.Point(260, 440)
    $btnRemoveSelected.Size = New-Object System.Drawing.Size(120, 30)
    $btnRemoveSelected.Add_Click({
        $selectedGroups = @()
        for ($i = 0; $i -lt $groupListBox.Items.Count; $i++) {
            if ($groupListBox.GetItemChecked($i)) {
                $selectedGroups += $groupListBox.Items[$i]
            }
        }
        
        if ($selectedGroups.Count -gt 0) {
            $result = Remove-SelectedGroups -TargetPC $TargetPC -GroupsToRemove $selectedGroups
            if ($result) {
                $form.Close()
                Show-GroupManagementForm -TargetPC $TargetPC
            }
        }
    })
    
    $form.Controls.AddRange(@($groupListBox, $btnSelectAll, $btnSelectNone, $btnRemoveSelected))
    $form.ShowDialog()
}

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

    # Add event handler for Manage Groups button
    $btnManageGroups.Add_Click({
        Show-GroupManagementForm -TargetPC $txtTargetPC.Text
    })

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
        $fileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $fileDialog.Filter = "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*"
        $fileDialog.DefaultExt = "csv"
        if ($fileDialog.ShowDialog() -eq "OK") {
            $txtLogPath.Text = $fileDialog.FileName
        }
    })

    $btnStart.Add_Click({
        if (-not $txtSourcePC.Text -or -not $txtTargetPC.Text -or -not $txtSourceFolder.Text -or -not $txtTargetFolder.Text -or -not $txtLogPath.Text) {
            [System.Windows.Forms.MessageBox]::Show("Please fill in all fields.", "Validation Error", "OK", "Warning")
            return
        }
        
        $global:SourcePC = $txtSourcePC.Text
        $global:TargetPC = $txtTargetPC.Text
        $global:RootFolder = $txtSourceFolder.Text
        $global:LogPath = $txtLogPath.Text
        
        Start-PermissionMigration -SourcePC $global:SourcePC -TargetPC $global:TargetPC -SourcePath $global:RootFolder -TargetPath $global:RootFolder
    })

    $btnExit.Add_Click({
        $form.Close()
    })

    $form.ShowDialog()
}
