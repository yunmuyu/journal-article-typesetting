param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop'
$inputFile=(Get-Item -LiteralPath $InputPath).FullName
$outputFile=[IO.Path]::GetFullPath($OutputPath)
Import-Module (Join-Path $PSScriptRoot 'JournalBottomSolver.psm1') -Force
$request=Get-Content -LiteralPath $inputFile -Raw -Encoding UTF8 | ConvertFrom-Json
$plan=New-JournalBottomPlan -InputObject $request
if($request.PSObject.Properties['preservation']){$plan|Add-Member -NotePropertyName preservation -NotePropertyValue $request.preservation}
if($request.PSObject.Properties['deferred']){$plan|Add-Member -NotePropertyName deferred -NotePropertyValue $request.deferred}
if($request.PSObject.Properties['frameExpansions']){$plan|Add-Member -NotePropertyName frameExpansions -NotePropertyValue $request.frameExpansions}
if($request.PSObject.Properties['deferred'] -and @($request.deferred).Count){
    $plan.status='blocked'
    $plan.blockedColumns=@($plan.blockedColumns)+@($request.deferred|ForEach-Object{"$($_.kind):$($_.reason)"})
}
$parent=[IO.Path]::GetDirectoryName($outputFile); if(-not [IO.Directory]::Exists($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
[IO.File]::WriteAllText($outputFile,($plan|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
$plan
if($plan.status -eq 'blocked'){throw "BOTTOM_PLAN_BLOCKED $($plan.blockedColumns -join ',')"}
