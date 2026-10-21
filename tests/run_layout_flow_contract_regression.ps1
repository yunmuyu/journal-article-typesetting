param()
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$entry=[IO.File]::ReadAllText((Join-Path $project '2-导入_InDesign\Invoke-JournalLayout.ps1'),[Text.Encoding]::UTF8)
$rules=[IO.File]::ReadAllText((Join-Path $project '2-导入_InDesign\journal_layout_rules.jsxinc'),[Text.Encoding]::UTF8)
[void][scriptblock]::Create($entry)
$checks=[ordered]@{
 'frontmatter module is loaded by the single document entry'=$entry.Contains('journal_frontmatter.jsxinc') -and $entry.Contains('JournalFrontmatter.apply')
 'layout mutations are one InDesign undo transaction'=$entry.Contains("UndoModes.ENTIRE_SCRIPT,'Journal layout transaction'")
 'failed Apply does not save'=$entry.IndexOf("if(`$apply&&result.errors.length)",[StringComparison]::Ordinal) -ge 0 -and $entry.IndexOf("if(`$apply&&result.errors.length)",[StringComparison]::Ordinal) -lt $entry.IndexOf("if(`$apply) d.save()",[StringComparison]::Ordinal)
 'check mode never mutates role labels or document ruler state'=$rules.Contains('bind(d,c,apply)') -and $rules.Contains("if(!apply)throw Error('BINDING_ROLE_MISMATCH") -and $rules.Contains('d.viewPreferences.rulerOrigin=RulerOrigin.PAGE_ORIGIN;d.zeroPoint=[0,0];}bind(d,c,apply)') -and -not $rules.Contains('d.zeroPoint=[0,0];bind(d,c);')
 'entry never changes activeDocument as an implicit target'=-not $entry.Contains('app.activeDocument=d')
 'document close is guarded by canonical path and document id'=$entry.Contains('function closeExact') -and $entry.Contains('TARGET_PATH_CHANGED') -and $entry.Contains('TARGET_ID_CHANGED')
 'pre-existing user documents are never closed by CloseWhenDone'=$entry.Contains('if($closeWhenDoneJs&&opened)closeExact(d,SaveOptions.YES)')
 'unguarded activeDocument close is forbidden'=-not $entry.Contains('activeDocument.close')
 'short first metadata column falls back to measured guide position'=-not $rules.Contains('FIRST_COLUMN_INK_GAP_UNRESOLVED') -and $rules.Contains('return Math.abs(inkBounds(frame.lines[-1])[2]-target)')
 'lower guide follows actual body ink and fixed height'=$rules.Contains("FOOTER_SPACING','body ink to lower guide")
 'citation superscript stays with preceding visible character'=$rules.Contains('if(i===1&&start>0)') -and $rules.Contains('while(previous>=0&&/\s/.test(text.charAt(previous)))')
 'wide panels break only after a complete paragraph without forcing long paragraph into one frame'=$rules.Contains('keepAllLinesTogether===true') -and $rules.Contains('boundary.requireBeforePage===true')
 'article page-range audits use only configured bound stories'=$rules.Contains('c.bindings.length') -and $rules.Contains('stories.itemByID(c.bindings[bi].id)') -and $rules.Contains('storySeen')
 'standalone wide-caption stories do not require a body gap paragraph'=$rules.Contains("if(stories[k].extractLabel('journal-role')!=='body')continue;")
 'multi-level headings must retain heading style'=$rules.Contains("err('HEADING_STYLE'")
 'second-level headings are kept during apply and audited by actual placement'=$rules.Contains("r==='h2'") -and $rules.Contains('p.keepWithNext=1') -and $rules.Contains("err('HEADING_ORPHAN'") -and -not $rules.Contains("err('HEADING_KEEP'")
}
$failed=@($checks.GetEnumerator()|Where-Object{-not $_.Value})
if($failed.Count){throw 'Layout flow contract regression failed: '+(($failed|ForEach-Object Key)-join '; ')}
& node (Join-Path $PSScriptRoot 'bottom_interval_behavior_regression.js')
if($LASTEXITCODE -ne 0){throw 'Bottom interval behavior regression failed'}
'PASS single-session frontmatter, transactional save gate, measured gray guide and heading guards'
