param(
    [Parameter(Mandatory=$true)][string]$TaskPath,
    [string]$OutputPath
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'JournalPreflight.psm1') -Force
$task=Read-JournalJson $TaskPath
if(-not $OutputPath){$OutputPath=Join-Path $task.outputDirectory 'layout-plan.json'}
$plan=New-JournalPreflightPlan $task
Write-JournalJsonAtomic $plan $OutputPath
$plan|ConvertTo-Json -Depth 30
if($plan.status -eq 'needs_input'){exit 2}
