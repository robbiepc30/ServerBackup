properties {
    $ProjectRoot = "$PSScriptRoot\ServerBackup"
}
Task Analyze {
    $saResults = Invoke-ScriptAnalyzer -Path $ProjectRoot -Severity Error, Warning -Recurse
    if ($saResults){
        $saResults 
        Write-Error "One or more Script Analyzer errors/Warrnings where found.  Build cannot continue!"
    }
}
Task Test {
    $testResults = Invoke-Pester -Script $PSScriptRoot -PassThru
    if($testResults.FailedCount -ne 0) {
        Write-Error "Failed '$($testResults.FailedCount)' test.  Build cannot continue!"
    }
}

Task Default -depends Analyze, Test

Task Deploy -depends Analyze, Test {
    Invoke-PSDeploy -Path $PSScriptRoot -Force -Verbose:$VerbosePreference
}