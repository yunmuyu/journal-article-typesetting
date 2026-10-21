# 把 import_word_article_to_indesign.jsx 安装到本机所有 InDesign 的脚本面板目录。
# 用法：双击同目录的 "安装脚本到InDesign-双击我.bat"，或：
#   powershell -ExecutionPolicy Bypass -File deploy_to_indesign.ps1
param([switch]$NoPause)
$ErrorActionPreference = "Stop"
function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','') }
    finally { $algorithm.Dispose(); $stream.Dispose() }
}
$src = Join-Path $PSScriptRoot "import_word_article_to_indesign.jsx"
if (-not (Test-Path -LiteralPath $src)) { throw "同目录下找不到 import_word_article_to_indesign.jsx" }
$base = Join-Path $env:APPDATA "Adobe\InDesign"
if (-not (Test-Path -LiteralPath $base)) { throw "没找到 InDesign 用户目录: $base （请先安装并运行一次 InDesign）" }
$panels = @()
foreach ($ver in (Get-ChildItem -LiteralPath $base -Directory)) {
    foreach ($loc in (Get-ChildItem -LiteralPath $ver.FullName -Directory)) {
        $p = Join-Path $loc.FullName "Scripts\Scripts Panel"
        if (Test-Path -LiteralPath $p) { $target=Join-Path $p "期刊文章自动排版系统"; [void][IO.Directory]::CreateDirectory($target); $panels += $target }
    }
}
if ($panels.Count -eq 0) {
    throw "没找到任何 Scripts Panel 目录。请先把 InDesign 打开一次再重试。"
} else {
    $sourceHash = Get-Sha256 $src
    $backupRoot = Join-Path $env:LOCALAPPDATA ('JournalArticleTypesetting\backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    $panelIndex = 0
    foreach ($p in $panels) {
        foreach ($name in @('import_word_article_to_indesign.jsx', '0文章.jsx', 'journal_layout_rules.jsxinc', 'journal_prepreview_gate.jsxinc', 'journal_bottom_plan.jsxinc', 'journal_layout_and_check.jsx')) {
            $fileSource=if($name -in @('import_word_article_to_indesign.jsx','0文章.jsx')){$src}else{Join-Path $PSScriptRoot $name}
            $fileHash=Get-Sha256 $fileSource
            $destination = Join-Path $p $name
            if (Test-Path -LiteralPath $destination) {
                $backup = Join-Path $backupRoot ([string]$panelIndex)
                [void][IO.Directory]::CreateDirectory($backup)
                Copy-Item -LiteralPath $destination -Destination (Join-Path $backup $name)
            }
            Copy-Item -LiteralPath $fileSource -Destination $destination -Force
            if ((Get-Sha256 $destination) -ne $fileHash) { throw "部署哈希不一致: $destination" }
        }
        $panelIndex++
        Write-Host "[已安装] $p" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "完成。0文章.jsx 与 import_word_article_to_indesign.jsx 均已更新，SHA256: $sourceHash" -ForegroundColor Cyan
    Write-Host "旧脚本备份: $backupRoot"
}
if (-not $NoPause -and $env:W2ID_NO_PAUSE -ne '1') { [void](Read-Host "回车退出") }
