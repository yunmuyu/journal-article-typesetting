function Invoke-JournalInDesignScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Application,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Code
    )
    $engine=[Environment]::GetEnvironmentVariable('JOURNAL_SCRIPT_ENGINE')
    if([string]::IsNullOrEmpty($engine)){$engine='journal-production-v1'}
    if($engine -cnotmatch '\A[A-Za-z0-9_-]+\z'){throw 'INDESIGN_SCRIPT_ENGINE_INVALID'}
    $script='#targetengine "'+$engine+'"'+"`n"+$Code
    return $Application.DoScript($script,1246973031)
}
Export-ModuleMember -Function Invoke-JournalInDesignScript
