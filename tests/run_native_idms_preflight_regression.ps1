$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$entryPoint=Join-Path $PSScriptRoot '../2-导入_InDesign/Invoke-JournalArticleAssembly.ps1'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('journal-idms-assembly-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot|Out-Null
try{
    $snippet=Join-Path $testRoot 'formula-1.idms'
    [IO.File]::WriteAllText($snippet,'synthetic snippet; no Adobe execution')
    $entry=@{number=1;path=$snippet;sha256=(Get-FileHash -LiteralPath $snippet).Hash;widthMm=4;heightMm=3;basePointSize=10.5}
    $config=@{schemaVersion=1;outputPath=(Join-Path $testRoot 'article_QA.indd');templatePath=(Join-Path $testRoot 'template.indd');inputs=@();panels=@();taskId='synthetic';formulas=@{mode='native-idms';entries=@($entry)}}
    $configPath=Join-Path $testRoot 'job.json'
    function Invoke-Plan {
        [IO.File]::WriteAllText($configPath,($config|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
        & $entryPoint -ConfigPath $configPath -PlanOnly
    }
    function Expect-Failure([string]$Code){
        $failure=$null
        try{Invoke-Plan|Out-Null}catch{$failure=$_.Exception.Message}
        if(-not $failure -or $failure -notmatch [regex]::Escape($Code)){throw "EXPECTED $Code; GOT $failure"}
    }
    $plan=Invoke-Plan|ConvertFrom-Json
    if($plan.inputsVerified -ne 1 -or $plan.status -ne 'ready-for-assembly'){throw 'VALID_IDMS_PLAN_FAILED'}
    $originalHash=$entry.sha256
    $entry.sha256='0'*64;Expect-Failure 'FORMULA_IDMS_CHANGED';$entry.sha256=$originalHash
    $entry.sha256='';Expect-Failure 'FORMULA_IDMS_HASH_REQUIRED';$entry.sha256=$originalHash
    $entry.basePointSize=9;Expect-Failure 'FORMULA_IDMS_BASE_SIZE';$entry.basePointSize=10.5
    $entry.widthMm=0;Expect-Failure 'FORMULA_IDMS_DIMENSION';$entry.widthMm=4
    $entry.number=1.5;Expect-Failure 'FORMULA_IDMS_NUMBER';$entry.number=1
    $config.formulas.entries=@($entry,$entry);Expect-Failure 'FORMULA_IDMS_NUMBER';$config.formulas.entries=@($entry)
    $entry.path=Join-Path $testRoot 'formula.pdf';Expect-Failure 'FORMULA_IDMS_EXTENSION';$entry.path=$snippet
    $entry.path=Join-Path $testRoot 'missing.idms';Expect-Failure 'FORMULA_IDMS_MISSING';$entry.path=$snippet
    $entry.Remove('heightMm');Expect-Failure 'FORMULA_IDMS_FIELD_REQUIRED';$entry.heightMm=3
    if(Test-Path -LiteralPath $config.outputPath){throw 'PLAN_CREATED_DOCUMENT'}
    Write-Output 'PASS IDMS SHA256 preflight, required metadata, dimensions, 10.5pt, duplicate IDs and no Adobe/document writes'
}finally{
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'journal-idms-assembly-*'){throw 'TEST_CLEANUP_PATH'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
