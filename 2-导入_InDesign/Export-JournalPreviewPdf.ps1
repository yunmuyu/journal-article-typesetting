#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DocumentPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$ResultPath,
    [Parameter(Mandatory)][string]$PythonExe,
    [string]$PdfRenderValidator=$env:JOURNAL_PDF_RENDER_VALIDATOR,
    [int]$ExpectedPageCount=0,
    [int[]]$ArticlePageRange,
    [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$document=(Get-Item -LiteralPath $DocumentPath).FullName
$output=[IO.Path]::GetFullPath($OutputPath)
$resultFile=[IO.Path]::GetFullPath($ResultPath)
if([IO.Path]::GetExtension($document) -ine '.indd' -or [IO.Path]::GetFileName($document) -notmatch '(?i)QA|copy|副本'){throw 'PREVIEW_QA_REQUIRED'}
if([IO.Path]::GetExtension($output) -ine '.pdf'){throw 'PREVIEW_PDF_EXTENSION_REQUIRED'}
if([IO.Path]::GetExtension($resultFile) -ine '.json' -or $resultFile -ieq $document){throw 'PREVIEW_RESULT_PATH_INVALID'}
if($ExpectedPageCount -lt 0){throw 'PREVIEW_PAGE_COUNT_INVALID'}
if($PSBoundParameters.ContainsKey('ArticlePageRange') -and ($ArticlePageRange.Count -ne 2 -or $ArticlePageRange[0] -lt 0 -or $ArticlePageRange[1] -lt $ArticlePageRange[0])){throw 'PREVIEW_ARTICLE_PAGE_RANGE'}
if($PlanOnly){@{status='plan-only';document=$document;output=$output;resultPath=$resultFile;articlePageRange=$ArticlePageRange}|ConvertTo-Json;return}
Import-Module (Join-Path $PSScriptRoot 'JournalInDesignScript.psm1') -Force
if (!$PdfRenderValidator -or !(Test-Path -LiteralPath $PdfRenderValidator -PathType Leaf)) { throw 'PDF_RENDER_VALIDATOR_REQUIRED' }
Import-Module (Join-Path $PSScriptRoot 'JournalPdfValidation.psm1') -Force
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $output))
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $resultFile))
$temporary=Join-Path (Split-Path -Parent $output) ([IO.Path]::GetFileNameWithoutExtension($output)+'.partial-'+[guid]::NewGuid().ToString('N')+'.pdf')
$before=(Get-FileHash -LiteralPath $document -Algorithm SHA256).Hash
$job=@{path=$document;output=$temporary;articlePageRange=$ArticlePageRange}|ConvertTo-Json -Compress
$code=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_document_session.jsxinc'),[Text.Encoding]::UTF8)+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'journal_regression_snapshot.jsxinc'),[Text.Encoding]::UTF8)+"var PreviewJob=$job;"+@'
(function(job){var session=null,d=null,prefs=null,result;
 try{
  session=JournalDocumentSession.acquire(app,job.path);d=session.document;
  if(d.modified)throw Error('PREVIEW_DOCUMENT_UNSAVED');
  var count=d.pages.length,range=job.articlePageRange;
  if(range&&(range.length!==2||range[0]<0||range[1]<range[0]||range[1]>=count||Math.floor(range[0])!==range[0]||Math.floor(range[1])!==range[1]))throw Error('PREVIEW_ARTICLE_PAGE_RANGE');
  prefs={pageRange:app.pdfExportPreferences.pageRange,viewPDF:app.pdfExportPreferences.viewPDF,exportReaderSpreads:app.pdfExportPreferences.exportReaderSpreads};
  app.pdfExportPreferences.pageRange=range?('+'+(range[0]+1)+'-+'+(range[1]+1)):PageRange.ALL_PAGES;app.pdfExportPreferences.viewPDF=false;app.pdfExportPreferences.exportReaderSpreads=false;
  d.exportFile(ExportFormat.PDF_TYPE,File(job.output),false);
  if(!File(job.output).exists)throw Error('PDF_EXPORT_MISSING');
  result={status:'exported',pages:range?range[1]-range[0]+1:count,documentPages:count,articlePageRange:range||[0,count-1],openedHere:session.openedHere};
 }catch(e){result={status:'failed',error:String(e),line:e.line};}
 finally{
  if(prefs){app.pdfExportPreferences.pageRange=prefs.pageRange;app.pdfExportPreferences.viewPDF=prefs.viewPDF;app.pdfExportPreferences.exportReaderSpreads=prefs.exportReaderSpreads;}
  if(session&&session.openedHere){try{JournalDocumentSession.close(d,session,SaveOptions.NO);}catch(closeError){result={status:'failed',error:'PREVIEW_CLOSE '+closeError};}}
 }
 return JournalRegressionSnapshot.json(result);
})(PreviewJob);
'@
try {
    $app=New-Object -ComObject InDesign.Application.2020
    $raw=[string](Invoke-JournalInDesignScript -Application $app -Code $code)
    $native=$raw|ConvertFrom-Json
    if($native.status -ne 'exported'){throw "PDF_NATIVE_EXPORT_FAILED $raw"}
    $renderCheck=Test-JournalPdfRender -PdfPath $temporary -PythonExe $PythonExe -ValidatorPath $PdfRenderValidator
    $pdfCount=$renderCheck.page_count
    if([int]$pdfCount -ne [int]$native.pages){throw 'PDF_PAGE_COUNT_MISMATCH'}
    if($ExpectedPageCount -gt 0 -and [int]$pdfCount -ne $ExpectedPageCount){throw 'PDF_EXPECTED_PAGE_COUNT_MISMATCH'}
    if((Get-FileHash -LiteralPath $document -Algorithm SHA256).Hash -cne $before){throw 'PREVIEW_SOURCE_CHANGED'}
    Move-Item -LiteralPath $temporary -Destination $output -Force
    $result=@{passed=$true;status='preview-exported';renderCheck=$renderCheck;document=$document;documentSha256=$before;pdf=$output;pdfSha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash;pages=[int]$pdfCount;indesignPages=[int]$native.documentPages;articlePageRange=$native.articlePageRange;openedHere=$native.openedHere}
    [IO.File]::WriteAllText($resultFile,($result|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    $result|ConvertTo-Json -Depth 10
} catch {
    [IO.File]::WriteAllText($resultFile,(@{passed=$false;status='failed';error=$_.Exception.Message;partialPdf=$temporary}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    throw
}
