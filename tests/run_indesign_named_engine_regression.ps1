$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$directory=Join-Path (Split-Path $PSScriptRoot) '2-导入_InDesign'
Import-Module (Join-Path $directory 'JournalInDesignScript.psm1') -Force
$originalEngine=[Environment]::GetEnvironmentVariable('JOURNAL_SCRIPT_ENGINE')
$mock=[pscustomobject]@{Calls=[Collections.Generic.List[object]]::new();Result='MOCK_RESULT';Failure=$null}
$mock|Add-Member -MemberType ScriptMethod -Name DoScript -Value {
    param($Code,$Language)
    $this.Calls.Add(@{Code=$Code;Language=$Language})
    if($this.Failure){throw $this.Failure}
    return $this.Result
}
try{
    [Environment]::SetEnvironmentVariable('JOURNAL_SCRIPT_ENGINE',$null)
    $answer=Invoke-JournalInDesignScript -Application $mock -Code "var p=1;`n'OK';"
    if($answer -cne 'MOCK_RESULT' -or $mock.Calls.Count -ne 1){throw 'SCRIPT_RESULT_OR_CALL_COUNT'}
    if($mock.Calls[0].Code -cne ('#targetengine "journal-production-v1"'+"`nvar p=1;`n'OK';") -or $mock.Calls[0].Language -ne 1246973031){throw 'DEFAULT_ENGINE_PREFIX_OR_LANGUAGE'}
    [Environment]::SetEnvironmentVariable('JOURNAL_SCRIPT_ENGINE','Recovery_2026-10')
    $mock.Result=42
    $answer=Invoke-JournalInDesignScript -Application $mock -Code "'PING';"
    if($answer -isnot [int] -or $answer -ne 42 -or -not $mock.Calls[1].Code.StartsWith('#targetengine "Recovery_2026-10"')){throw 'OVERRIDE_OR_RESULT_TYPE'}
    foreach($name in @('bad engine','bad"engine','bad/engine',"bad`n",'中文','a.b')){
        [Environment]::SetEnvironmentVariable('JOURNAL_SCRIPT_ENGINE',$name)
        $before=$mock.Calls.Count;$failure=$null
        try{Invoke-JournalInDesignScript -Application $mock -Code "'NO_CALL';"|Out-Null}catch{$failure=$_.Exception.Message}
        if($failure -ne 'INDESIGN_SCRIPT_ENGINE_INVALID' -or $mock.Calls.Count -ne $before){throw 'INVALID_ENGINE_REACHED_APPLICATION'}
    }
    [Environment]::SetEnvironmentVariable('JOURNAL_SCRIPT_ENGINE',$null)
    $mock.Failure='RPC_E_SERVERFAULT'
    $failure=$null
    try{Invoke-JournalInDesignScript -Application $mock -Code "'FAIL';"|Out-Null}catch{$failure=$_.Exception.Message}
    if($failure -notmatch 'RPC_E_SERVERFAULT'){throw 'APPLICATION_FAILURE_SWALLOWED'}
    $expected=@('Build-JournalNativeFormulaManifest.ps1','Use-JournalFormulaNativeCache.ps1','Invoke-JournalArticleReview.ps1','Invoke-JournalArticleAssembly.ps1','Invoke-JournalLayout.ps1','Export-JournalLayoutMeasurement.ps1','Export-JournalRegressionSnapshot.ps1','Initialize-JournalQaTemplate.ps1','Invoke-JournalSlotAssembly.ps1','Replace-JournalFormulaNative.ps1')
    $total=0
    foreach($file in Get-ChildItem -LiteralPath $directory -Filter '*.ps1'){
        $tokens=$null;$parseErrors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
        if($parseErrors.Count){throw "SCRIPT_PARSE $($file.Name)"}
        $direct=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $node.Member.Value -eq 'DoScript'},$true))
        if($direct.Count){throw "UNMIGRATED_DOSCRIPT $($file.Name)"}
        $text=[IO.File]::ReadAllText($file.FullName)
        if($file.Name -in $expected){
            $calls=([regex]::Matches($text,'Invoke-JournalInDesignScript -Application')).Count
            if(-not $calls -or -not $text.Contains("Import-Module (Join-Path `$PSScriptRoot 'JournalInDesignScript.psm1') -Force")){throw "MISSING_HELPER_OR_IMPORT $($file.Name)"}
            $total+=$calls
        }
    }
    if($total -ne 14){throw "MIGRATED_CALL_COUNT $total"}
    Write-Output 'PASS named InDesign engine prefix, language, raw return value, explicit recovery override, invalid-name block, propagated application error and 14 migrated calls'
}finally{[Environment]::SetEnvironmentVariable('JOURNAL_SCRIPT_ENGINE',$originalEngine)}
