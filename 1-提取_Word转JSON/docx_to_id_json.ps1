# -*- coding: utf-8 -*-
# Word(.docx) -> InDesign 导入 JSON   （docx_to_id_json.py 的 PowerShell 版，给没装 Python 的机器用）
# 用法 1（拖拽）：把 .docx 拖到同目录的 "Word转JSON-拖这里.bat" 上
# 用法 2（命令行）：powershell -ExecutionPolicy Bypass -File docx_to_id_json.ps1 "你的.docx" ["输出.json"]
#
# 规则（与 docx_to_id_json.py 保持一致，改一边要同步另一边）：
#   - 从 "0 引言" 开始排，前面的标题/作者/摘要等全部跳过
#   - 保留参考文献和作者简介
#   - 表格内容跳过，所在位置保留 table_gap 空行
#   - MathType OLE 公式：独立行→"math"块+空行；行内→3 空格占位
#   - 图题前 3 空行，表题后 1 空行；(a)(b) 子图注保持 caption
#   - 保留 run 级：斜体 italic、加粗 bold、上标 superscript、下标 subscript
#   - w:i / w:b 检查 w:val 属性，防 val="false" 误判

param(
    [Parameter(Mandatory=$true)] [string]$DocxPath,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

# ⚠ 用 -LiteralPath：文件名里的 [ ] 是 PowerShell 通配符，普通 Test-Path/Resolve-Path 会把
#   "1  [图、表]  7P …" 当成通配模式而匹配不到真实文件。超长名/空格/【】/% 也一并兼容。
if (-not (Test-Path -LiteralPath $DocxPath)) { Write-Host "找不到文件: $DocxPath" -ForegroundColor Red; exit 1 }
$DocxPath = (Resolve-Path -LiteralPath $DocxPath).Path
if (-not $OutputPath) { $OutputPath = [System.IO.Path]::ChangeExtension($DocxPath, ".json") }

Add-Type -AssemblyName System.Xml
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# --- 旧版 .doc 支持：用 Word 自动化先转成临时 .docx 再走原流程 ---
# ⚠ 这台机器的 Word 类型库损坏（TYPE_E_CANTLOADLIBRARY），标准 COM 绑定/早绑定会报错；
#    必须用纯 IDispatch 后期绑定（GetTypeFromProgID + InvokeMember）才能调通。需要本机装有 Microsoft Word。
function Convert-DocToDocx([string]$srcDoc) {
    $tmp = [System.IO.Path]::Combine($env:TEMP, "w2id_" + [Guid]::NewGuid().ToString("N").Substring(0,8) + ".docx")
    $B = [System.Reflection.BindingFlags]
    $word = $null
    $docs = $null
    $d = $null
    try {
        $t = [Type]::GetTypeFromProgID("Word.Application")
        if (-not $t) { throw "本机未安装 Microsoft Word，无法转换 .doc。请先在 Word 里另存为 .docx。" }
        $word = [Activator]::CreateInstance($t)
        $t.InvokeMember("Visible",       $B::SetProperty, $null, $word, @($false)) | Out-Null
        $t.InvokeMember("DisplayAlerts", $B::SetProperty, $null, $word, @(0))      | Out-Null
        $docs = $t.InvokeMember("Documents", $B::GetProperty, $null, $word, $null)
        $d = $docs.GetType().InvokeMember("Open", $B::InvokeMethod, $null, $docs, @($srcDoc, $false, $true))  # ReadOnly
        # ⚠ 必须 [void]：InvokeMember 这些调用会把返回值（含 null）漏进函数输出流，导致 return 变成数组而非纯路径。
        [void]$d.GetType().InvokeMember("SaveAs2", $B::InvokeMethod, $null, $d, @($tmp, 16))                  # 16=wdFormatDocumentDefault(.docx)
    } finally {
        try {
            if ($d) {
                try { [void]$d.GetType().InvokeMember("Close", $B::InvokeMethod, $null, $d, @($false)) }
                finally { [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($d) }
            }
        } finally {
            try {
                if ($docs) { [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($docs) }
            } finally {
                if ($word) {
                    try { [void]$word.GetType().InvokeMember("Quit", $B::InvokeMethod, $null, $word, $null) }
                    finally { [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($word) }
                }
            }
        }
    }
    if (-not (Test-Path $tmp)) { throw "Word 转换失败，未生成临时 docx。" }
    return $tmp
}

$readPath = $DocxPath
$tempDocx = $null
if ([System.IO.Path]::GetExtension($DocxPath).ToLower() -eq ".doc") {
    Write-Host "检测到 .doc，正在用 Word 转换为 .docx ..." -ForegroundColor Yellow
    $tempDocx = Convert-DocToDocx $DocxPath
    $readPath = $tempDocx
}

# --- 读取 word/document.xml ---
$inputStream = [System.IO.File]::Open($readPath, 'Open', 'Read', 'ReadWrite')
try {
    $zip = New-Object System.IO.Compression.ZipArchive($inputStream, [System.IO.Compression.ZipArchiveMode]::Read)
    try {
        $entry = $zip.GetEntry("word/document.xml")
        if (-not $entry) { throw "这不是有效的 .docx（缺 document.xml）" }
        $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
        try { $rawXml = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $zip.Dispose() }
} finally { $inputStream.Dispose() }

. (Join-Path $PSScriptRoot 'WordNumbering.ps1')
$numberingXml='';$numberingStylesXml=''
$numberStream=[IO.File]::OpenRead($DocxPath)
try{$numberZip=New-Object IO.Compression.ZipArchive($numberStream,[IO.Compression.ZipArchiveMode]::Read)
 try{$numberEntry=$numberZip.GetEntry('word/numbering.xml');if($numberEntry){$nr=New-Object IO.StreamReader($numberEntry.Open());try{$numberingXml=$nr.ReadToEnd()}finally{$nr.Dispose()}}$styleEntry=$numberZip.GetEntry('word/styles.xml');if($styleEntry){$sr=New-Object IO.StreamReader($styleEntry.Open());try{$numberingStylesXml=$sr.ReadToEnd()}finally{$sr.Dispose()}}}finally{$numberZip.Dispose()}
}finally{$numberStream.Dispose()}
Initialize-WordNumbering $numberingXml $numberingStylesXml
$xdoc = New-Object System.Xml.XmlDocument
$xdoc.LoadXml($rawXml)
$W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
$ns = New-Object System.Xml.XmlNamespaceManager($xdoc.NameTable)
$ns.AddNamespace("w", $W)
$M = "http://schemas.openxmlformats.org/officeDocument/2006/math"
$ns.AddNamespace("m", $M)

# -- helpers --
function Test-FlagVal($rpr, [string]$tag) {
    $el = $rpr.SelectSingleNode("w:$tag", $ns)
    if (-not $el) { return $false }
    $v = $el.GetAttribute("val", $W)
    if (-not $v) { return $true }
    return ($v -ne "false" -and $v -ne "0" -and $v -ne "off")
}

function Test-HasOle($para) {
    foreach ($item in (Get-InlineItems $para)) {
        if ($item.NamespaceURI -eq $M -or $item.SelectSingleNode("w:object", $ns)) { return $true }
    }
    return $false
}

function Get-InlineItems($element) {
    foreach ($child in $element.ChildNodes) {
        if ($child.NamespaceURI -eq $W -and $child.LocalName -in @('del','moveFrom','pPr','rPr','sdtPr')) { continue }
        if (($child.NamespaceURI -eq $W -and $child.LocalName -eq 'r') -or ($child.NamespaceURI -eq $M -and $child.LocalName -eq 'oMath')) { $child }
        else { Get-InlineItems $child }
    }
}

function Get-RunContent($run) {
    $parts = New-Object System.Collections.ArrayList
    foreach ($child in $run.ChildNodes) {
        if ($child.NamespaceURI -ne $W) { continue }
        switch ($child.LocalName) {
            't' { [void]$parts.Add($child.InnerText) }
            { $_ -in @('object','drawing','pict') } { [void]$parts.Add('   ') }
            'tab' { [void]$parts.Add("`t") }
            { $_ -in @('br','cr') } { [void]$parts.Add("`n") }
            'noBreakHyphen' { [void]$parts.Add([string][char]0x2011) }
            'softHyphen' { [void]$parts.Add([string][char]0x00AD) }
        }
    }
    return (-join $parts)
}

function Get-Role([string]$t) {
    if ([string]::IsNullOrEmpty($t)) { return "blank" }
    if ($t -match '^参考文献[：:]?\s*$')              { return "references_title" }
    if ($t.StartsWith("作者简介"))                     { return "author_bio" }
    if ($t -match '^图\s*\d+\s+')                     { return "figure_caption" }
    if ($t -match '^表\s*\d+\s+')                     { return "table_caption" }
    if ($t -match '^[（(][a-zA-Z0-9一-鿿][）)]\s*\S')  { return "caption" }   # (a)(b) 子图注
    # 标题必须含汉字、且不含赋值箭头 ←（否则像 "4 sub ← copy(v)"、"8 if x ∈ T'" 这类算法伪代码会被误判成标题）
    if (($t -match '^\d+(?:\.\d+)+\s+\S') -and ($t -match '[一-龥]') -and ($t -notmatch '←')) { return "heading2" }
    if (($t -match '^\d+\s+\S') -and ($t.Length -le 40) -and ($t -match '[一-龥]') -and ($t -notmatch '←')) { return "heading1" }
    if ($t -match '^\[\d+\]')                          { return "reference_item" }
    return "body"
}

function Esc-Json([string]$s) {
    if ($null -eq $s) { return "null" }
    $s = $s -replace '\\','\\'
    $s = $s -replace '"','\"'
    $s = $s -replace "`r",'\r'
    $s = $s -replace "`n",'\n'
    $s = $s -replace "`t",'\t'
    return '"' + $s + '"'
}

$body = $xdoc.SelectSingleNode("//w:body", $ns)
$blocks = New-Object System.Collections.ArrayList
$seq = 0
$started = $false
$lastWasTable = $false

foreach ($child in $body.SelectNodes(".//w:p[not(ancestor::w:tbl) and not(ancestor::w:del) and not(ancestor::w:moveFrom)] | .//w:tbl[not(ancestor::w:tbl) and not(ancestor::w:del) and not(ancestor::w:moveFrom)]", $ns)) {
    if ($child.LocalName -eq 'tbl') {
        if ($started) {
            if ($lastWasTable -or $blocks.Count -eq 0 -or $blocks[$blocks.Count-1].role -ne 'table_gap') {
                [void]$blocks.Add(@{ role='table_gap'; text='   '; runs=@(); seq=0 })
            } else {
                $blocks[$blocks.Count-1].text = '   '
            }
            $lastWasTable = $true
        }
        continue
    }

    $textParts = New-Object System.Collections.ArrayList
    $runs = New-Object System.Collections.ArrayList
    $cursor = 0
    foreach ($r in (Get-InlineItems $child)) {
        if ($r.NamespaceURI -eq $M) {
            [void]$textParts.Add("   ")
            $cursor += 3
            continue
        }
        $t = Get-RunContent $r
        if ($t.Length -eq 0) { continue }
        $start = $cursor
        [void]$textParts.Add($t)
        $cursor += $t.Length
        $rpr = $r.SelectSingleNode("w:rPr", $ns)
        $flags = @{}
        if ($rpr) {
            if (Test-FlagVal $rpr "i")  { $flags["italic"] = $true }
            if (Test-FlagVal $rpr "b")  { $flags["bold"]   = $true }
            $va = $rpr.SelectSingleNode("w:vertAlign", $ns)
            if ($va) {
                $vv = $va.GetAttribute("val", $W)
                if ($vv -eq "superscript")   { $flags["position"] = "superscript" }
                elseif ($vv -eq "subscript") { $flags["position"] = "subscript" }
                # 只有“纯数字”的上下标强制直立（去斜体）；希腊字母等变量也保留 Word 原本的斜体。
                if (($vv -eq "superscript" -or $vv -eq "subscript") -and ($t -match '^\d+$')) {
                    [void]$flags.Remove("italic")
                }
            }
        }
        if ($flags.Count -gt 0) { [void]$runs.Add(@{ start=$start; end=$cursor; flags=$flags }) }
    }
    $text = -join $textParts
    $text = $text.Replace([string][char]0xFF0B, "+")   # 全角＋ → 半角+（不改字体）
    $numberPrefix=Get-WordNumberPrefix $child $ns
    if($numberPrefix){foreach($run in $runs){$run.start+=$numberPrefix.Length;$run.end+=$numberPrefix.Length};$text=$numberPrefix+$text}
    $isOle = (Test-HasOle $child)
    $seq++

    # -- 独立 MathType 公式（文本空 + OLE）→ math 占位 + 空行 --
    if ($text.Trim().Length -eq 0) {
        if ($isOle -and $started) {
            $lastWasTable = $false
            [void]$blocks.Add(@{ role="math"; text=""; runs=@(); seq=$seq })
            $seq++
            [void]$blocks.Add(@{ role="blank"; text=""; runs=@(); seq=$seq })
        }
        # 普通空行仍然跳过
        continue
    }

    $lastWasTable = $false
    $cleaned = [regex]::Replace($text.Trim(), "[ `t　]+", " ")
    $role = Get-Role $cleaned

    # -- 前置跳过逻辑 --
    if (-not $started) {
        if (($role -eq "heading1") -and ($cleaned -match '^0\s+引\s*言$')) { $started = $true }
        else { continue }
    }

    # 参考文献 / 作者简介 现在也排版（不再跳过）。
    # ⚠ 这些段落在 Word 里常被整段误设为粗体，去掉 bold，由段落样式（参考文献 内容 / 作者简介）决定字重；
    #    保留 italic / 上下标（外文文献偶有）。字符样式由导入脚本按位置补（见 jsx）。
    if ($role -eq "references_title" -or $role -eq "reference_item" -or $role -eq "author_bio") {
        $cleanRuns = New-Object System.Collections.ArrayList
        foreach ($rr in $runs) {
            $f = $rr.flags.Clone()
            [void]$f.Remove("bold")
            if ($f.Count -gt 0) { [void]$cleanRuns.Add(@{ start=$rr.start; end=$rr.end; flags=$f }) }
        }
        $runs = $cleanRuns
    }

    # -- 图前 3 空行（图注/表名样式）。若上一块是 (a)(b) 子图注，空行插到它前面，
    #    使顺序为：空行 空行 空行 → (a)(b)子图注 → 图题 --
    if ($role -eq "figure_caption") {
        $insertAt = $blocks.Count
        if (($blocks.Count -gt 0) -and ($blocks[$blocks.Count - 1].role -eq "caption")) {
            $insertAt = $blocks.Count - 1
        }
        for ($k = 0; $k -lt 3; $k++) {
            [void]$blocks.Insert($insertAt + $k, @{ role="figure_caption"; text=""; runs=@(); seq=0 })
        }
    }

    # 内嵌 MathType 占位已在上面的 run 循环中处理（每个 OLE 对象 = 3 空格，偏移对齐）。

    [void]$blocks.Add(@{ role=$role; text=$text; runs=$runs; seq=$seq })

    # -- 表名后 1 空行（role=table_gap，导入时左对齐、无缩进，给表格留位）--
    if ($role -eq "table_caption") {
        [void]$blocks.Add(@{ role="table_gap"; text=""; runs=@(); seq=0 })
    }
}

# 重编号 seq
for ($i = 0; $i -lt $blocks.Count; $i++) { $blocks[$i].seq = $i + 1 }

# --- 序列化 JSON（手写，避开 PS5.1 ConvertTo-Json 对空/单元素数组的坑）---
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("{")
[void]$sb.AppendLine("  " + (Esc-Json "source") + ": " + (Esc-Json $DocxPath) + ",")
[void]$sb.AppendLine("  " + (Esc-Json "blocks") + ": [")
for ($i = 0; $i -lt $blocks.Count; $i++) {
    $b = $blocks[$i]
    [void]$sb.Append("    {" + (Esc-Json "role") + ": " + (Esc-Json $b.role) + ", " + (Esc-Json "text") + ": " + (Esc-Json $b.text) + ", " + (Esc-Json "runs") + ": [")
    for ($j = 0; $j -lt $b.runs.Count; $j++) {
        $r = $b.runs[$j]; $f = $r.flags
        $rj = "{" + (Esc-Json "start") + ": " + $r.start + ", " + (Esc-Json "end") + ": " + $r.end
        if ($f.ContainsKey("position")) { $rj += ", " + (Esc-Json "position") + ": " + (Esc-Json $f['position']) }
        if ($f.ContainsKey("italic"))   { $rj += ", " + (Esc-Json "italic") + ": true" }
        if ($f.ContainsKey("bold"))     { $rj += ", " + (Esc-Json "bold") + ": true" }
        $rj += "}"
        [void]$sb.Append($rj)
        if ($j -lt $b.runs.Count - 1) { [void]$sb.Append(", ") }
    }
    [void]$sb.Append("], " + (Esc-Json "seq") + ": " + $b.seq + "}")
    if ($i -lt $blocks.Count - 1) { [void]$sb.AppendLine(",") } else { [void]$sb.AppendLine() }
}
[void]$sb.AppendLine("  ],")

$summary = [ordered]@{}
foreach ($b in $blocks) { if (-not $summary.Contains($b.role)) { $summary[$b.role] = 0 }; $summary[$b.role]++ }
[void]$sb.Append("  " + (Esc-Json "summary") + ": {")
$keys = @($summary.Keys)
for ($i = 0; $i -lt $keys.Count; $i++) {
    [void]$sb.Append((Esc-Json $keys[$i]) + ": " + $summary[$keys[$i]])
    if ($i -lt $keys.Count - 1) { [void]$sb.Append(", ") }
}
[void]$sb.AppendLine("}")
[void]$sb.Append("}")

[System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))

if ($tempDocx -and (Test-Path -LiteralPath $tempDocx)) { Remove-Item -LiteralPath $tempDocx -Force -ErrorAction SilentlyContinue }   # 清理 .doc 转换的临时 docx

Write-Host ""
Write-Host "OK 已生成: $OutputPath" -ForegroundColor Green
Write-Host "   段落总数: $($blocks.Count)"
Write-Host "   结构统计:"
foreach ($k in $summary.Keys) { Write-Host ("     {0,-18} {1}" -f $k, $summary[$k]) }
Write-Host ""
