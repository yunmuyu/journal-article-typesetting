param([Parameter(Mandatory=$true)][string]$ConfigPath,[Parameter(Mandatory=$true)][string]$ReportPath,[string[]]$ReviewNotes=@())
$ErrorActionPreference='Stop'
$c=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
$r=Get-Content -LiteralPath ([IO.Path]::ChangeExtension($c.auditPath,'.result.json')) -Raw -Encoding UTF8|ConvertFrom-Json
if(-not $r.passed -or $r.document -ne $c.documentPath){throw 'A passing audit for this document is required'}
if((Get-Item -LiteralPath $c.documentPath).LastWriteTimeUtc -gt (Get-Item -LiteralPath $c.auditPath).LastWriteTimeUtc){throw 'Document changed after audit; run Check again'}
[xml]$audit=Get-Content -LiteralPath $c.auditPath -Raw -Encoding UTF8
$figures=@($audit.SelectNodes('/audit/figure')|Sort-Object {[int]$_.number})
$assets=@($c.assets|Where-Object kind -eq 'figure')
if($figures.Count -ne $assets.Count){throw 'Figure metadata missing; run Check with the current module'}
$rows=@()
foreach($f in $figures){
 $a=@($assets|Where-Object { [int]$_.number -eq [int]$f.number -and $_.name -ceq $f.name -and [IO.Path]::GetFullPath($_.source) -ieq [IO.Path]::GetFullPath($f.path) });if($a.Count -ne 1){throw 'Figure number/name/path mismatch'}
 if($f.name -cne $a[0].name -or [IO.Path]::GetFullPath($f.path) -ine [IO.Path]::GetFullPath($a[0].source)){throw 'Original figure link mismatch'}
 if((Get-FileHash -LiteralPath $f.path -Algorithm SHA256).Hash -cne $a[0].sha256){throw 'Figure changed after audit; run Check again'}
 $scale=[double]$f.scaleX;if([math]::Abs($scale-[double]$f.scaleY) -gt .01){throw 'Nonuniform figure scaling requires review'}
 $change=if([math]::Abs($scale-100) -lt .001){'不变'}elseif($scale -gt 100){'放大 '+([math]::Round($scale-100,3))+'%'}else{'缩小 '+([math]::Round(100-$scale,3))+'%'}
 $rows+=[pscustomobject]@{figure=([string]$f.number+[string]$f.part);page=$f.page;position=$f.position;left_mm=[double]$f.left;top_mm=[double]$f.top;source=$f.path;source_width_mm=[double]$f.sourceWidth;source_height_mm=[double]$f.sourceHeight;target_width_mm=[double]$f.width;target_height_mm=[double]$f.height;scale_percent=$scale;change=$change;font_compensation_factor=100/$scale}
}
$lines=[Collections.Generic.List[string]]::new();$lines.Add('# 作图AI交接清单');$lines.Add('');$lines.Add('更新：'+(Get-Date -Format yyyy-MM-dd)+'。从已通过检查的实际InDesign测试稿读取，原图路径和文件名不变。');$lines.Add('');$lines.Add('版面：`'+$c.documentPath+'`');$lines.Add('');$lines.Add('| 图号 | 位置 | 原100%尺寸/mm | 目标尺寸/mm | 当前比例 | 调整 |');$lines.Add('|---|---|---|---|---|---|')
foreach($f in $rows){$lines.Add(('| 图{0} | {1}页{2}，距页顶{3:F2} mm | {4:F2} × {5:F2} | {6:F2} × {7:F2} | {8:F3}% | {9} |' -f $f.figure,$f.page,$f.position,$f.top_mm,$f.source_width_mm,$f.source_height_mm,$f.target_width_mm,$f.target_height_mm,$f.scale_percent,$f.change))}
$lines.Add('');$lines.Add('## 作图AI复核');$lines.Add('');$lines.Add('- 按目标物理尺寸复核文字、刻度、图例、上下标、单位和线宽，保持全篇协调；不改图形含义和数据。');$lines.Add('- 推荐在目标成品尺寸下调整文字并输出。抵消当前整体缩放的字号变化时，源文字字号乘100/当前比例；JSON/CSV已给出font_compensation_factor，仅供计算参考，具体字体字号按作图线程确认的期刊标准。');$lines.Add('- 改图后由排版端更新链接、按目标尺寸置入，并重查图题5 pt、正文重排和底对齐，不沿用改图前检查状态。');foreach($note in $ReviewNotes){$lines.Add('- '+$note)}
$lines.Add('');$lines.Add('## 原图路径');$lines.Add('');foreach($f in $rows){$lines.Add(('- 图{0}：`{1}`' -f $f.figure,$f.source))}
$full=[IO.Path]::GetFullPath($ReportPath);[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full));[IO.File]::WriteAllText($full,($lines -join "`r`n"),[Text.UTF8Encoding]::new($false))
$rows|Export-Csv -LiteralPath ([IO.Path]::ChangeExtension($full,'.csv')) -NoTypeInformation -Encoding utf8BOM
[IO.File]::WriteAllText([IO.Path]::ChangeExtension($full,'.json'),($rows|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
'PASS '+$rows.Count+' figures: '+$full
