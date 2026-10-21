param()
$ErrorActionPreference = 'Stop'

$project = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $project '2-导入_InDesign\journal_frontmatter.jsxinc'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw 'Missing journal_frontmatter.jsxinc'
}

$source = [IO.File]::ReadAllText($modulePath)
foreach ($forbidden in @('alert(', 'confirm(', 'prompt(', 'openDialog(', 'activeDocument', 'app.selection')) {
    if ($source.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Interactive Adobe dependency found: $forbidden"
    }
}
foreach ($required in @('Justification.LEFT_JUSTIFIED', 'FRAME_TOP_FIXED', 'FOOTER_BOTTOM_FIXED', 'BODY_START_FROM_INK', 'paragraph.spaceAfter', 'paragraph-style', 'englishStyleContract')) {
    if ($source.IndexOf($required, [StringComparison]::Ordinal) -lt 0) {
        throw "Missing front-matter contract marker: $required"
    }
}

$hostScript = @"
$source
function fail(message) { throw new Error(message); }
function near(actual, expected, tolerance, message) {
    if (Math.abs(actual - expected) > tolerance) fail(message + ': ' + actual + ' != ' + expected);
}

var title = JournalFrontmatter.planEnglishTitle(2, {
    enTitleUpperLeadingPt: 15.75,
    enTitleLastLeadingPt: 17,
    enTitleAuthorBaselineGapPt: 15.089
});
near(title.lineLeadings[0], 15.75, 0.0001, 'upper title line must be independently adjustable');
near(title.lineLeadings[1], 17, 0.0001, 'last title line must retain normal title-author spacing');
near(title.authorBaselineGapPt, 15.089, 0.0001, 'title-author baseline gap must remain explicit');

var input = {
    frontHeightMm: 78,
    frontInkBottomMm: 109.25,
    bodyBounds: [[120, 14.5, 265, 97.5], [120, 103, 265, 186]],
    bodyFirstInkTopMm: [123.1, 122.7],
    footerHeightMm: 18,
    footerFirstInkOffsetMm: 3.2
};
var config = {
    frontAnchor: {top: 30.35, left: 21.1, width: 164.9},
    footerAnchor: {bottom: 265.04, left: 14.5, width: 85.5},
    topGrayHeightMm: 8.75,
    bottomGrayHeightMm: 5.5,
    footerInkGapMm: 8.668790147681,
    footerGuideOffsetMm: 0.889113498331,
    metadataFrameInsetMm: 1.356145536731
};
var plan = JournalFrontmatter.planGeometry(input, config);
near(plan.frontBounds[0], 30.35, 0.0001, 'front top is fixed');
near(plan.frontBounds[2], 109.25, 0.0001, 'front frame grows only at bottom and contains ink');
near(plan.topGrayBounds[0], 109.25, 0.0001, 'top gray begins at visible ink');
near(plan.topGrayBounds[2], 118, 0.0001, 'top gray height');
near(plan.bodyBounds[0][0] + (123.1 - 120), 118, 0.0001, 'left body visible ink starts after gray');
near(plan.bodyBounds[1][0] + (122.7 - 120), 118, 0.0001, 'right body visible ink starts after gray');
near(plan.footerBounds[2], 265.04, 0.0001, 'footer bottom is fixed');
near(plan.footerBounds[0], 247.04, 0.0001, 'footer grows upward');
near(plan.bodyBounds[0][2], plan.targetBodyInkBottomMm + 1.356145536731, 0.0001, 'body frame ends at ink plus inset');
near(plan.bottomGrayBounds[2] - plan.bottomGrayBounds[0], 5.5, 0.0001, 'bottom gray height');
if (plan.log.length < 4) fail('structured operation log is incomplete');

var taller = JournalFrontmatter.planGeometry({
    frontHeightMm: input.frontHeightMm,
    frontInkBottomMm: input.frontInkBottomMm,
    bodyBounds: input.bodyBounds,
    bodyFirstInkTopMm: input.bodyFirstInkTopMm,
    footerHeightMm: 24,
    footerFirstInkOffsetMm: input.footerFirstInkOffsetMm
}, config);
near(taller.footerBounds[2], plan.footerBounds[2], 0.0001, 'multi-line fund must preserve footer bottom');
if (!(taller.footerBounds[0] < plan.footerBounds[0])) fail('multi-line fund must grow upward');

WScript.Echo('PASS silent front-matter planning and fixed anchors');
"@

$fixture = Join-Path ([IO.Path]::GetTempPath()) ("journal-frontmatter-{0}.js" -f [Guid]::NewGuid().ToString('N'))
try {
    [IO.File]::WriteAllText($fixture, $hostScript, [Text.Encoding]::Unicode)
    $output = & "$env:SystemRoot\System32\cscript.exe" //nologo $fixture 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join [Environment]::NewLine) }
    $output
} finally {
    Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue
}
