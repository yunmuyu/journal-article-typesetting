param(
    [Parameter(Mandatory=$true)][string]$PythonPath,
    [string[]]$DocxPaths = @(),
    [string]$ImporterPath
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'run_batch_preflight_regression.ps1')
& (Join-Path $PSScriptRoot 'run_qa_template_initializer_regression.ps1')
& (Join-Path $PSScriptRoot 'run_slot_component_regression.ps1')
& (Join-Path $PSScriptRoot 'run_formula_cache_regression.ps1')
& (Join-Path $PSScriptRoot 'run_asset_cache_pipeline_regression.ps1')
& (Join-Path $PSScriptRoot 'run_layout_flow_contract_regression.ps1')
& (Join-Path $PSScriptRoot 'run_prepreview_gate_regression.ps1')
& (Join-Path $PSScriptRoot 'run_session_entry_regression.ps1')
& $PythonPath (Join-Path $PSScriptRoot 'test_extraction.py')
if ($LASTEXITCODE -ne 0) { throw 'Extraction and BAT regressions failed' }
& (Join-Path $PSScriptRoot 'run_frontmatter_module_regression.ps1')
& (Join-Path $PSScriptRoot 'run_bottom_solver_regression.ps1')
& (Join-Path $PSScriptRoot 'run_bottom_plan_apply_regression.ps1')
& (Join-Path $PSScriptRoot 'run_word_cleanup_regression.ps1')
$app = New-Object -ComObject 'InDesign.Application.2020'
$copyCheck = $app.DoScript('app.documents.length>0 && /qa|副本|copy/i.test(app.activeDocument.name) ? "COPY" : "OTHER";', 1246973031)
if ($copyCheck -ne 'COPY') { throw 'Open a formal document copy named QA, copy or 副本 before running InDesign tests' }
foreach ($name in @(
    'run_format_regression.ps1',
    'run_indesign_bold_italic_regression.ps1',
    'run_indesign_inherited_character_style_regression.ps1',
    'run_indesign_script_italic_regression.ps1',
    'run_indesign_chinese_italic_regression.ps1',
    'run_indesign_special_glyph_regression.ps1',
    'run_indesign_superscript_leading_regression.ps1'
)) {
    Write-Host $name
    $arguments = @{}
    if ($ImporterPath -and $name -ne 'run_format_regression.ps1') { $arguments.ImporterPath = $ImporterPath }
    & (Join-Path $PSScriptRoot $name) @arguments
}
foreach ($docx in $DocxPaths) {
    & (Join-Path $PSScriptRoot 'run_real_article_regression.ps1') -DocxPath $docx -PythonPath $PythonPath -ImporterPath $ImporterPath
}
Write-Host 'PASS all requested extraction, BAT and InDesign regressions'
