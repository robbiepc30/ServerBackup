function Start-ServerBackup {
<#
.Synopsis
   Creates a Windows Full Backup of server to a network location.
.DESCRIPTION
   Creates a Windows Full Backup of server to location specified in the NetworkPath parameter,
   and keeps the 10 most current backups. One of the backups is the oldest that is less than 6 months old.
.EXAMPLE
   BackupServer.ps1 -NetworkPath "\\Server\Share"
#>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true, HelpMessage="Enter a UNC path like \\Server\Share")]
        [ValidatePattern("^\\\\\w+\\\w+")]
        [String]$NetworkPath
    )
    # TODO: use validation or Split-Path & Join-Path to verifiy, or fix a trailing "\" or "space"
    # this will screw up the $backupLocationRoot an $backupLocation paths currently.

    if (!(Test-Path $NetworkPath)) {
        throw "Network Path does not exist or cannot connect to network path"
    }

    $dateString = $((Get-Date).ToString("yyyy-MM-dd-HH-mm-ss"))
    $folderName = "$env:COMPUTERNAME.$dateString"
    $backupLocationRoot = "$networkPath\$env:COMPUTERNAME"
    $backupLocation = "$networkPath\$env:COMPUTERNAME\$folderName"

    try {
        # Create Backup folder, no checking if path exist because foldername has the current
        # timestamp in name that includes the second, chance of it already existing are next 
        # to none. (famouse last words...)

        New-Item -itemtype directory -path $backupLocation -ErrorAction Stop | Out-Null

        Start-BackupCleanup -NetworkPath $backupLocationRoot -ErrorAction Stop
        Start-WindowsBackupFullNetwork -NetworkPath $backupLocation -ErrorAction Stop
    }
    catch {
        throw
    }
}

function Start-BackupCleanup {
<#
.Synopsis
   Cleans up backup location to keep the most relevent backups based on the -MaxCount parameter (default 10)
.DESCRIPTION
   Cleans up backup location to keep the most relevent backups based on the -MaxCount parameter (default 10)
   If the oldest backup is less than 6 months old it is kept and the newest backups
   If the oldest backup is older than 6 months then only the newest backups are kept
.EXAMPLE
   Use The default max count of 10
   Start-BackupCleanup -NetworkPath "\\Server\Share\ComputerName"
.EXAMPLE
   Start-BackupCleanup -NetworkPath "\\Server\Share\ComputerName" -MaxCount 20
   Keeps up to 20 backups in network location
#>
    [CmdletBinding()]
    Param
    (
        # Param1 help description
        [Parameter(Mandatory=$true, HelpMessage="Enter a UNC path like \\server\share\ComputerName")]
        # Protection form accidental deletion, ensure that network path also has name of server,
        # this helps prevents a bad, but valid path being used that then acidently deletes folders in this path        
        [ValidateScript({$_ -like "*$env:COMPUTERNAME"})] 
        [String]
        $NetworkPath,
        [Int]
        $MaxCount = 10
    )
    # TODO: Fix cleanup to keeep the oldest backup that is less than 6 months old, and not just the newest backups
    #       when the oldest backup is older than 6 months. 
    #       Currently it just keeps the newest backups if the oldest backup is older than 6 months, not really
    #       what I want.  I really want to keep the oldest backup that is less than 6 months and then the newest
    #       backups.       

    if (!(Test-Path $NetworkPath)) {
        throw "Network Path does not exist or cannot connect to network path"
    }

    # PS v2.0 compatibility, Get-ChildItem -Directory switch not available
    $count = (Get-ChildItem -Path $NetworkPath | Where-Object {$_.PSIsContainer}).Count
    $removeFolderCount = $count - $MaxCount

    if ($removeFolderCount -gt 0) {
        
        # PS v2.0 compatibility, Get-ChildItem -Directory switch not available
        $folderList = Get-ChildItem -Path $NetworkPath | Where-Object {$_.PSIsContainer} | Sort-Object -Property CreationTime
        $oldestFolderDate = $folderList | Select-Object -First 1 -ExpandProperty CreationTime
        $sixMonthsAgo = $((Get-Date).AddDays(-180))

        # remove oldest folders
        # Do this if the oldest folder is past 6 months old
        # a date that is less than another date in computing terms is acctully older, confusing sometimes
        if ($oldestFolderDate -lt $sixMonthsAgo) {
            $removeFolder = $folderList | Select-Object -First $removeFolderCount -ExpandProperty FullName

            # PS v2.0 compatibility, Remove-Item -Recurse switch is broken in PowerShell v2.0, known bug
            Get-ChildItem -path $removeFolder -Recurse | Select-Object -ExpandProperty FullName  | Sort-Object -Descending | Remove-Item
            Remove-Item $removeFolder
        }
        # remove oldest folders, EXCEPT the very oldest folder
        # remove all but the oldest folder if its less than 6 months old
        else {
            # make folder list as an arrayList instead of an array, this allows me to remove items from array
            # Increase list by 1 because the last (oldest folder record) will be removed from ArrayList to keep the oldest folder
            # done by "select -Last ($removeFolderCount + 1)" instead of "select -Last $removeFolderCount"
            [System.Collections.ArrayList]$removeFolder = $folderList | Select-Object -First ($removeFolderCount + 1) -ExpandProperty FullName
                
            # remove oldest entry
            $removeFolder.RemoveAt(0)
            Get-ChildItem -path $removeFolder -Recurse | Select-Object -ExpandProperty FullName  | Sort-Object -Descending | Remove-Item
            Remove-Item $removeFolder
        }
    }
    else {
        Write-Output "Nothing to clean up"
    }

    # When v2.0 compatibility no longer matters do it this way
    # $removeFolder | Remove-Item -Recurse

}

function Start-WindowsBackupFullNetwork {
<#
.Synopsis
   Uses Windows Backup to take a Full backup of all Volumes and SystemState to a NetworkShare.
.DESCRIPTION
   Uses Windows Backup to take a Full backup of all Volumes and SystemState to a NetworkShare.
.EXAMPLE
   Start-WindowsBackupFullNetwork -NetworkPath \\server\share
.EXAMPLE
   Another example of how to use this cmdlet
#>
    [CmdletBinding()]
    Param
    (
        # Param1 help description
        [Parameter(Mandatory=$true, HelpMessage="Enter a UNC path like \\Server\Share")]
        [ValidatePattern("^\\\\\w+\\\w+")]
        [String]
        $NetworkPath
    )
    # Set ErorAction to Stop for all cmldlets used and put in a try/catch block
    # even termenating errors will continue to run on a cmdlet, this is not what I want
    # if a termenating error occurs I want to re throw the error and cause it to terminate
    # For more information check out "The Big Book Of Powershell Error Handling" page 18
    $ErrorActionPreference = "Stop"

    try {
        Add-PSSnapin windows.serverbackup

        $policy = New-WBPolicy
        $target = New-WBBackupTarget -NetworkPath $NetworkPath
        Add-WBBackupTarget -Policy $policy -Target $target

        # Full Server Backup, includes System State, Bare Metal Recovery and all Volumes
        $volume = Get-WBVolume -AllVolumes
        Add-WBVolume -Policy $policy -Volume $volume
        Add-WBBareMetalRecovery -Policy $policy
        Add-WBSystemState -Policy $policy

        # Set for VSS Full Backup
        Set-WBVssBackupOptions -Policy $policy -VssFullBackup

        Start-WBBackup -Policy $policy
    }
    catch {
        throw
    }  
}

Export-ModuleMember BackupServer