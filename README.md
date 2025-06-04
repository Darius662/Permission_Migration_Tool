# Permission Migration Tool

A PowerShell-based tool for migrating permissions between Windows PCs, copying local groups, and managing permissions.

## Features

- Copy permissions between PCs
- Copy local groups between PCs
- Backup ~~and restore~~ permissions
- ~~Compare permissions between paths~~
- User-friendly GUI interface
- ~~Detailed CSV logging~~
- Progress tracking
- Group management capabilities

## Prerequisites

- Windows PowerShell 5.1 or higher
- PowerShell remoting enabled on both source and target PCs
- Administrative rights on both PCs
- Network connectivity between PCs

## Getting Started

1. **Run the Script**
   - Open **PowerShell ISE** as Administrator
   - Open the script in PS ISE
   - F5 or Run

2. **Main Interface**
   - **Source PC (PC1):** Enter the name of the source computer
   - **Target PC (PC2):** Enter the name of the target computer
   - **Source Folder (on PC1):** Browse to select the folder with permissions to copy
   - **Target Folder (on PC2):** Enter the UNC path (\\PC2\ShareName)
   - **Log File Path:** Browse to select where to save the CSV log

3. **Recommended Workflow**
   a. ~~**Test Connection**~~
      - ~~Click "Test Connection" to verify both PCs are reachable~~
   
   b. **Manage Groups**
      - Click "Manage Groups" to open group management
      - Select unwanted groups to remove
      - Click "Remove Selected" to clean up groups
   
   c. **Start Migration**
      - Click "Start Migration" to begin the process
      - Monitor progress in the progress bar and log output

## Functions

1. **Manage Groups**
   - View all local groups on target PC
   - Select groups to remove
   - ~~Protected groups (Administrators, Users, etc.) cannot be removed~~

2. ~~**Compare Permissions**~~
   - ~~Compare permissions between source and target folders~~
   - ~~Shows differences in access rules, owners, and groups~~

3. ~~**Restore Backup**~~
   - ~~Restore permissions from a previous backup~~
   - ~~Select backup file using file dialog~~

## Logging

- All operations are logged to a ~~CSV~~ TXT file
- Log contains:
  - Timestamp
  - Operation level (INFO, WARNING, ERROR, SUCCESS)
  - Detailed operation messages
- Log file can be opened in ~~Excel~~ **any text editor** for analysis

## Troubleshooting

1. **Connection Issues**
   - Verify PowerShell remoting is enabled
   - Check firewall rules
   - Ensure both PCs are online

2. **Permission Issues**
   - Run PowerShell as Administrator
   - Verify administrative rights on both PCs
   - Check network permissions for UNC paths

3. **Failed Operations**
   - Check the log file for error messages
   - Use "Compare Permissions" to verify results
   - ~~Consider restoring from backup if needed~~

## Security Notes

- The tool requires administrative rights
- Always verify target folder exists before migration
- Keep backups of important permissions
- Document any permission changes made
