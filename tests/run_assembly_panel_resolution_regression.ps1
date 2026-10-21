$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$source=Join-Path $PSScriptRoot '../2-导入_InDesign/Invoke-JournalArticleAssembly.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'ASSEMBLY_PS_PARSE'}
$definition=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Save-ResolvedAssemblyPanels'},$true)
. ([scriptblock]::Create($definition.Extent.Text))
$workRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../work'))
$testRoot=Join-Path $workRoot ('journal-panel-resolution-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot|Out-Null
try{
    $configPath=Join-Path $testRoot 'job.json'
    $original='{"schemaVersion":1,"custom":{"text":"保留原字段","values":[1,true,null]},"panels":[{"numbers":[1,3],"columns":2,"pageTop":false,"afterParagraphText":"段落甲"},{"numbers":[2],"columns":1,"pageTop":false,"extra":{"keep":true}}]}'
    function Reset-Job {
        [IO.File]::WriteAllText($configPath,$original,[Text.UTF8Encoding]::new($false))
        return ($original|ConvertFrom-Json)
    }
    $result='{"status":"assembled-unchecked","panels":[{"numbers":[2],"pageTop":false},{"numbers":[3,1],"pageTop":true}]}'|ConvertFrom-Json
    $job=Reset-Job
    Save-ResolvedAssemblyPanels $job $result 'Assemble' $configPath
    $saved=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not $saved.panels[0].pageTop -or $saved.panels[1].pageTop){throw 'MIXED_PANELS_NOT_MATCHED_BY_NUMBERS'}
    $saved.panels[0].pageTop=$false
    if(($saved|ConvertTo-Json -Depth 80 -Compress) -ne (($original|ConvertFrom-Json)|ConvertTo-Json -Depth 80 -Compress)){throw 'OTHER_JOB_FIELDS_CHANGED'}
    foreach($stage in @('NormalizeExisting','ReflowExisting','LayoutExisting','ApplyBottomExisting')){
        $job=Reset-Job;Save-ResolvedAssemblyPanels $job $result $stage $configPath
        if([IO.File]::ReadAllText($configPath) -cne $original -or $job.panels[0].pageTop){throw "NON_ASSEMBLE_WRITE $stage"}
    }
    $job=Reset-Job;$result.status='failed';Save-ResolvedAssemblyPanels $job $result 'Assemble' $configPath
    if([IO.File]::ReadAllText($configPath) -cne $original){throw 'FAILED_ASSEMBLE_WRITE'}
    $job=Reset-Job;$result.status='assembled-unchecked';$result.panels[1].numbers=@(99)
    try{Save-ResolvedAssemblyPanels $job $result 'Assemble' $configPath;throw 'EXPECTED_IDENTITY_FAILURE'}catch{if($_.Exception.Message -notmatch 'ASSEMBLY_PANEL_RESOLUTION_IDENTITY'){throw}}
    if([IO.File]::ReadAllText($configPath) -cne $original -or $job.panels[0].pageTop){throw 'PARTIAL_RESOLUTION_WRITE'}
    $job=Reset-Job;$result.panels[1].numbers=@(1,3);$result.panels[1].pageTop=$false
    Save-ResolvedAssemblyPanels $job $result 'Assemble' $configPath
    if([IO.File]::ReadAllText($configPath) -cne $original){throw 'UNCHANGED_PLAN_REWRITTEN'}
    $sourceText=[IO.File]::ReadAllText($source)
    if($sourceText.IndexOf('Save-ResolvedAssemblyPanels $job $result $Stage $ConfigPath') -lt $sourceText.IndexOf('$result=$raw|ConvertFrom-Json')){throw 'PERSIST_BEFORE_ASSEMBLY_RESULT'}
    Write-Output 'PASS resolved pageTop persists by panel number identity; mixed panels, unknown fields, failed/non-Assemble/no-change and partial failure remain safe'
}finally{
    $resolved=[IO.Path]::GetFullPath($testRoot);$tempRoot=$workRoot+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'journal-panel-resolution-*'){throw 'TEST_CLEANUP_PATH'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
