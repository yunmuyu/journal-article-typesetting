param([Parameter(Mandatory)][string]$PythonExe,[Parameter(Mandatory)][string]$ValidatorPath,[Parameter(Mandatory)][string]$ValidPdf,[Parameter(Mandatory)][string]$InvalidPdf)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '../2-导入_InDesign/JournalPdfValidation.psm1') -Force
$report=Test-JournalPdfRender -PdfPath $ValidPdf -PythonExe $PythonExe -ValidatorPath $ValidatorPath
if(!$report.passed -or $report.rendered_pages -ne $report.page_count){throw 'VALID_RENDER_NOT_VERIFIED'}
$rejected=$false
try{Test-JournalPdfRender -PdfPath $InvalidPdf -PythonExe $PythonExe -ValidatorPath $ValidatorPath | Out-Null}catch{if($_.Exception.Message -notmatch 'PDF_RENDER_FAILED'){throw};$rejected=$true}
if(!$rejected){throw 'CORRUPT_PDF_ACCEPTED'}
'PASS shared renderer accepts complete valid PDF and rejects corrupt stream'
