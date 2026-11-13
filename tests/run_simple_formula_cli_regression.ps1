param([Parameter(Mandatory)][string]$PythonExe)
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('journal-simple-'+[guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($root)
try {
 $source=Join-Path $root 'source.docx';$output=Join-Path $root 'converted.docx';$report=Join-Path $root 'report.json'
 $xml='<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"><w:body><w:p><w:r><w:t>变量</w:t></w:r><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:hint="eastAsia"/><w:i/><w:b/><w:vertAlign w:val="subscript"/><w:position w:val="-3"/></w:rPr><w:t>ij</w:t></w:r><w:r><w:t>[J]</w:t></w:r><m:oMath><m:r><m:t>x</m:t></m:r></m:oMath></w:p></w:body></w:document>'
 $zip=[IO.Compression.ZipFile]::Open($source,[IO.Compression.ZipArchiveMode]::Create)
 try {$writer=[IO.StreamWriter]::new($zip.CreateEntry('word/document.xml').Open());try{$writer.Write($xml)}finally{$writer.Dispose()}}finally{$zip.Dispose()}
 $hash=(Get-FileHash -LiteralPath $source).Hash
 & $PythonExe (Join-Path $PSScriptRoot '../tools/simple-formula/mathtype_to_word_text.py') $source --output $output --report $report
 if($LASTEXITCODE -ne 0){throw 'CLI_FAILED'}
 $result=Get-Content -LiteralPath $report -Raw|ConvertFrom-Json
 if($result.omml_converted_count -ne 1 -or $result.font_normalized_count -ne 1 -or $result.ordinary_runs_with_position_preserved -ne 1 -or (Get-FileHash -LiteralPath $source).Hash -ne $hash){throw 'CONVERSION_CONTRACT'}
 $zip=[IO.Compression.ZipFile]::OpenRead($output)
 try{$reader=[IO.StreamReader]::new($zip.GetEntry('word/document.xml').Open());try{[xml]$doc=$reader.ReadToEnd()}finally{$reader.Dispose()}}finally{$zip.Dispose()}
 $ns=[Xml.XmlNamespaceManager]::new($doc.NameTable);$ns.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main')
 $index=$doc.SelectSingleNode('//w:r[w:t="ij"]',$ns)
 if(!$index.SelectSingleNode('w:rPr/w:i',$ns) -or !$index.SelectSingleNode('w:rPr/w:b',$ns) -or $index.SelectSingleNode('w:rPr/w:vertAlign',$ns).GetAttribute('val',$ns.LookupNamespace('w')) -ne 'subscript'){throw 'INDEX_FORMAT_CHANGED'}
 if($doc.SelectSingleNode('//w:r[w:t="[J]"]/w:rPr/w:i',$ns)){throw 'REFERENCE_ITALIC'}
 'PASS synthetic DOCX CLI conversion, source hash, italic/bold subscript, reference and position preservation'
} finally {
 Get-ChildItem -LiteralPath $root -File | Remove-Item
 Remove-Item -LiteralPath $root
}
