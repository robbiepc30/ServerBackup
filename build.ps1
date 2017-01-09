#Requires -PSSnapin windows.serverbackup -Modules Pester, psake, PSScriptAnalyzer, PSDeploy
[CmdletBinding()]
param(
    [string[]]$Task = 'default'
)

Invoke-psake -buildFile "$PSScriptRoot\psake.ps1" -taskList $Task -Verbose:$VerbosePreference