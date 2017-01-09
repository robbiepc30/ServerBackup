$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.ps1", ".psm1")
$module = ($sut -split '.',0,'simplematch')[0]

# Import Module and Snapins for test
Import-Module "$here\..\ServerBackup\$sut" -Force
Add-PSSnapin windows.serverbackup

InModuleScope -ModuleName $module {
    Function SetupTestDrive {
    $path =  "TestDrive:\$env:COMPUTERNAME"
    $folderList =  1..50 | foreach{"Folder$_"} 

    foreach ($folder in $folderList) {
    
        New-Item -Name $folder -ItemType directory -Path $path
    
        foreach($number in 1..5){
            New-Item -Name "folder$number" -ItemType directory -Path "$path\$folder"
            New-Item -Name "$number.something.txt" -Path "$path\$folder\folder$number" -ItemType File 
            New-Item -Name "$number.something.txt" -Path "$path\$folder" -ItemType File
        }
        # Delay so folder time stamps are far enough away, otherwise timestamps are too close, and can cause errors in testing
        Start-Sleep -Milliseconds 1
    }
}
    
    Describe "Start-ServerBackup" {
        Context "Bad Network Path" {
        # Mocks
            Mock New-Item {}
            Mock Start-BackupCleanup {}
            Mock Start-WindowsBackupFullNetwork {}
            Mock Test-Path {$false}

            It "Bad NetworkPath throws error" {
                {Start-ServerBackup -NetworkPath "\\server\badpath"} | Should throw "Network Path does not exist or cannot connect to network path"
            }
        }
        Context "Good Network Path" {
        
            $share = "\\server\share"
            $dateString = (New-Object DateTime(2015,1,1,1,1,1)).ToString("yyyy-MM-dd-HH-mm-ss")
            $folderName = "$env:COMPUTERNAME.$dateString"
            $backupLocationRoot = "$share\$env:COMPUTERNAME"
            $backupLocation = "$share\$env:COMPUTERNAME\$folderName"
        
            # Just In case mocks, to prevent actull cmdlets from running
            Mock New-Item {}
            Mock Start-BackupCleanup {}
            Mock Start-WindowsBackupFullNetwork {}

            # Mocks that should be used
            Mock Test-Path {$true}
            Mock Get-Date {New-Object DateTime(2015,1,1,1,1,1)}
            Mock Start-BackupCleanup {} -ParameterFilter {$NetworkPath -eq $backupLocationRoot}
            Mock Start-WindowsBackupFullNetwork -ParameterFilter {$NetworkPath -eq $backupLocation}
            Mock New-Item {} -ParameterFilter {$Path -eq $backupLocation}

            Start-ServerBackup -NetworkPath $share
        
            It "Creates Root backup folder" {
            Assert-MockCalled New-Item -ParameterFilter {$Path -eq $backupLocation} -Exactly 1 -Scope Context
        }

            It "Runs Start-BackupCleanup" {
            Assert-MockCalled Start-BackupCleanup -ParameterFilter {$NetworkPath -eq $backupLocationRoot} -Exactly 1 -Scope Context
        }

            It "Runs Start-WindowsBackupFullNetwork" {
            Assert-MockCalled Start-WindowsBackupFullNetwork -ParameterFilter {$NetworkPath -eq $backupLocation} -Exactly 1 -Scope Context
        }

        }   
    }

    Describe "Start-BackupCleanup" {
  
        Context "Uses Default MaxCount. Oldest backup is less than 6 months old" {
            SetupTestDrive

            It "Remove all but 10 backups" {
                Start-BackupCleanup -NetworkPath "TestDrive:\$env:COMPUTERNAME"
                (Get-ChildItem -Path "TestDrive:\$env:COMPUTERNAME").Count | Should Be 10
            }
            It "Kept the oldest, and the 9 latest backups" {
                $folderPath = @("TestDrive:\$env:COMPUTERNAME\Folder1")
                $folderPath += 42..50 | foreach{"TestDrive:\$env:COMPUTERNAME\Folder$_"}
                Test-Path $folderPath | Should be $true
            }
        }

        Context "Uses 20 as -MaxCount Parameter. Oldest backup is less than 6 months old" {
            SetupTestDrive

            It "Removes all but 20 backups" {
                Start-BackupCleanup -NetworkPath "TestDrive:\$env:COMPUTERNAME" -MaxCount 20
                (Get-ChildItem -Path "TestDrive:\$env:COMPUTERNAME").Count | Should Be 20
            }

            It "Kept the oldest, and the 19 latest backups" {
                $folderPath = @("TestDrive:\$env:COMPUTERNAME\Folder1")
                $folderPath += 32..50 | foreach{"TestDrive:\$env:COMPUTERNAME\Folder$_"}
                Test-Path $folderPath | Should be $true
            }

        }

        Context "Backup is older than 180 days, using default for -MaxCount" {
            SetupTestDrive
            $oneYearFromNow = (Get-Date).AddDays(360)
            Mock Get-Date {$oneYearFromNow}

            It "Remove all but 10 backups" {
                Start-BackupCleanup -NetworkPath "TestDrive:\$env:COMPUTERNAME"
                (Get-ChildItem -Path "TestDrive:\$env:COMPUTERNAME").Count | Should Be 10
            }

            It "Kept the 10 latest backups" {
                $folderPath = 41..50 | foreach{"TestDrive:\$env:COMPUTERNAME\Folder$_"}
                Test-Path $folderPath | Should be $true
            }
   
        }

        Context "Backup is older than 180 days, using  -MaxCount 20" {
            SetupTestDrive
            $oneYearFromNow = (Get-Date).AddDays(360)
            Mock Get-Date {$oneYearFromNow}

            It "Remove all but 20 backups" {
                Start-BackupCleanup -NetworkPath "TestDrive:\$env:COMPUTERNAME" -MaxCount 20
                (Get-ChildItem -Path "TestDrive:\$env:COMPUTERNAME").Count | Should Be 20
            }

            It "Kept the 20 latest backups" {
                $folderPath = 31..50 | foreach{"$TestDrive\$env:COMPUTERNAME\Folder$_"}
                Test-Path $folderPath | Should be $true
            }

        } 

        Context "Number of backups is > or = to -MaxCount, no backups get removed" {
            SetupTestDrive

            Mock Write-Output {} -ParameterFilter {$InputObject -eq "Nothing to clean up"}
            It "Number of backups is = to -MaxCount, no backups get removed" {
                Start-BackupCleanup -NetworkPath "TestDrive:\$env:COMPUTERNAME" -MaxCount 50
                Assert-MockCalled Write-Output -ParameterFilter {$InputObject -eq "Nothing to clean up"} -Exactly 1 -Scope It

            }

            It "Number of backups is > -MaxCount, no backups get removed" {
                Start-BackupCleanup -NetworkPath "TestDrive:\$env:COMPUTERNAME" -MaxCount 59
                Assert-MockCalled Write-Output -ParameterFilter {$InputObject -eq "Nothing to clean up"} -Exactly 1 -Scope It
            }

        }

        Context "Validation" {

            It "Bad -NetworkPath should throw error" {
                {Start-BackupCleanup -NetworkPath "c:\a bad path\$env:COMPUTERNAME"} | Should throw "Network Path does not exist or cannot connect to network path"
            }

            $errorMessage = 'Cannot validate argument on parameter ''NetworkPath''. The "$_ -like "*$env:COMPUTERNAME"" validation script for the argument with value "TestDrive:\backup\DontDelte" did not return true. Determine why the validation script failed and then try the command again.'
            It "Path that does not end with the ComputerName should throw error" {
                 {Start-BackupCleanup -NetworkPath "TestDrive:\backup\DontDelte"} | Should throw $errorMessage
            }

        }

    
    }

    Describe "Start-WindowsBackupFullNetwork" {

        Context "Add-WBBackupTarget stops function when NON-TERMINATING error is thrown" {
        
            # Mocks
            Mock New-WBBackupTarget {Write-Error "New-WBBackupTarget error"}
            Mock Add-WBBackupTarget {}
            Mock Get-WBVolume {}
            Mock Add-WBVolume {}
            Mock Add-WBBareMetalRecovery {}
            Mock Add-WBSystemState {}
            Mock Set-WBVssBackupOptions {}
            Mock Start-WBBackup {}

            It "New-WBBackupTarget should throw error" {
                {Start-WindowsBackupFullNetwork -NetworkPath "\\somepath\someshare"} | Should throw "New-WBBackupTarget error"
            }

            It "Cmdlets that should NOT run are NOT called" {
                Assert-MockCalled Add-WBBackupTarget -Exactly 0 -Scope Context
                Assert-MockCalled Get-WBVolume -Exactly 0 -Scope Context
                Assert-MockCalled Add-WBVolume -Exactly 0 -Scope Context
                Assert-MockCalled Add-WBBareMetalRecovery -Exactly 0 -Scope Context
                Assert-MockCalled Add-WBSystemState -Exactly 0 -Scope Context
                Assert-MockCalled Set-WBVssBackupOptions -Exactly 0 -Scope Context
                Assert-MockCalled Start-WBBackup -Exactly 0 -Scope Context
            }
    
        }

        Context "Add-WBBackupTarget stops function when NON-TERMINATING error is thrown" {
        
            # Mocks
            Mock Add-WBBackupTarget {Write-Error "Add-WBBackupTarget error"}
            Mock Get-WBVolume {}
            Mock Add-WBVolume {}
            Mock Add-WBBareMetalRecovery {}
            Mock Add-WBSystemState {}
            Mock Set-WBVssBackupOptions {}
            Mock Start-WBBackup {}

            It "New-WBBackupTarget should throw error" {
                {Start-WindowsBackupFullNetwork -NetworkPath "\\somepath\someshare"} | Should throw "Add-WBBackupTarget error"
            }

            It "Cmdlets that should NOT run are NOT called" {   
                Assert-MockCalled Get-WBVolume -Exactly 0 -Scope Context
                Assert-MockCalled Add-WBVolume -Exactly 0 -Scope Context
                Assert-MockCalled Add-WBBareMetalRecovery -Exactly 0 -Scope Context
                Assert-MockCalled Add-WBSystemState -Exactly 0 -Scope Context
                Assert-MockCalled Set-WBVssBackupOptions -Exactly 0 -Scope Context
                Assert-MockCalled Start-WBBackup -Exactly 0 -Scope Context
            }
    
        }

        Context "Get-WBVolume stops function when TERMINATING error is thrown" {
        
            # Mocks
            Mock Add-WBBackupTarget {}
            Mock Get-WBVolume {throw "Get-WBVolume error"}
            Mock Add-WBVolume {}
            Mock Add-WBBareMetalRecovery {}
            Mock Add-WBSystemState {}
            Mock Set-WBVssBackupOptions {}
            Mock Start-WBBackup {}

            It "Get-WBVolume error should throw error" {
                {Start-WindowsBackupFullNetwork -NetworkPath "\\somepath\someshare"} | Should throw "Get-WBVolume error"
            }

            It "Cmdlets that should NOT run are NOT called" {   
                Assert-MockCalled Add-WBVolume -Exactly 0 -Scope Context
                Assert-MockCalled Add-WBBareMetalRecovery -Exactly 0 -Scope Context
                Assert-MockCalled Add-WBSystemState -Exactly 0 -Scope Context
                Assert-MockCalled Set-WBVssBackupOptions -Exactly 0 -Scope Context
                Assert-MockCalled Start-WBBackup -Exactly 0 -Scope Context
            }
    
        }

        Context "Add-WBVolume stops function when TERMINATING error is thrown" {
        
            # Mocks
            Mock Add-WBBackupTarget {}
            Mock Add-WBVolume {throw "Add-WBVolume error"}
            Mock Add-WBBareMetalRecovery {}
            Mock Add-WBSystemState {}
            Mock Set-WBVssBackupOptions {}
            Mock Start-WBBackup {}

            It "Get-WBVolume error should throw error" {
                {Start-WindowsBackupFullNetwork -NetworkPath "\\somepath\someshare"} | Should throw "Add-WBVolume error"
            }

            It "Cmdlets that should NOT run are NOT called" {   
                Assert-MockCalled Add-WBBareMetalRecovery -Exactly 0 -Scope Context
                Assert-MockCalled Add-WBSystemState -Exactly 0 -Scope Context
                Assert-MockCalled Set-WBVssBackupOptions -Exactly 0 -Scope Context
                Assert-MockCalled Start-WBBackup -Exactly 0 -Scope Context
            }
    
        }

        Context "Add-WBBareMetalRecovery stops function when TERMINATING error is thrown" {
        
            # Mocks
            Mock Add-WBBackupTarget {}
            Mock Add-WBBareMetalRecovery {throw "Add-WBBareMetalRecovery error"}
            Mock Add-WBSystemState {}
            Mock Set-WBVssBackupOptions {}
            Mock Start-WBBackup {}

            It "Get-WBVolume error should throw error" {
                {Start-WindowsBackupFullNetwork -NetworkPath "\\somepath\someshare"} | Should throw "Add-WBBareMetalRecovery error"
            }

            It "Cmdlets that should NOT run are NOT called" {   
                Assert-MockCalled Add-WBSystemState -Exactly 0 -Scope Context
                Assert-MockCalled Set-WBVssBackupOptions -Exactly 0 -Scope Context
                Assert-MockCalled Start-WBBackup -Exactly 0 -Scope Context
            }
    
        }

        Context "Add-WBSystemState stops function when TERMINATING error is thrown" {
        
            # Mocks
            Mock Add-WBBackupTarget {}
            Mock Add-WBSystemState {throw "Add-WBSystemState error"}
            Mock Set-WBVssBackupOptions {}
            Mock Start-WBBackup {}

            It "Get-WBVolume error should throw error" {
                {Start-WindowsBackupFullNetwork -NetworkPath "\\somepath\someshare"} | Should throw "Add-WBSystemState error"
            }

            It "Cmdlets that should NOT run are NOT called" {   
                Assert-MockCalled Set-WBVssBackupOptions -Exactly 0 -Scope Context
                Assert-MockCalled Start-WBBackup -Exactly 0 -Scope Context
            }
    
        }

        Context "Set-WBVssBackupOptions stops function when TERMINATING error is thrown" {
        
            # Mocks
            Mock Add-WBBackupTarget {}
            Mock Set-WBVssBackupOptions {throw "Set-WBVssBackupOptions error"}
            Mock Start-WBBackup {}

            It "Get-WBVolume error should throw error" {
                {Start-WindowsBackupFullNetwork -NetworkPath "\\somepath\someshare"} | Should throw "Set-WBVssBackupOptions error"
            }

            It "Cmdlets that should NOT run are NOT called" {   
                Assert-MockCalled Start-WBBackup -Exactly 0 -Scope Context
            }
    
        }

        Context "Start-WBBackup stops function when TERMINATING error is thrown" {
        
            # Mocks
            Mock Add-WBBackupTarget {}
            Mock Start-WBBackup {throw "Start-WBBackup error"}

            It "Get-WBVolume error should throw error" {
                {Start-WindowsBackupFullNetwork -NetworkPath "\\somepath\someshare"} | Should throw "Start-WBBackup error"
            }    
        }

    }

}