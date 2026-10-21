param([Parameter(Mandatory=$true)][string]$SourceDocx,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead((Get-Item -LiteralPath $SourceDocx).FullName)
try {
 $reader=[IO.StreamReader]::new($zip.GetEntry('word/document.xml').Open())
 try {[xml]$xml=$reader.ReadToEnd()}finally{$reader.Dispose()}
 $ns=[Xml.XmlNamespaceManager]::new($xml.NameTable);$ns.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main')
 $runs=[Collections.Generic.List[object]]::new();$merges=[Collections.Generic.List[object]]::new();$ti=0
 foreach($table in $xml.SelectNodes('/w:document/w:body/w:tbl',$ns)){
  $ri=0
  foreach($row in $table.SelectNodes('w:tr',$ns)){
   $ci=0
   foreach($cell in $row.SelectNodes('w:tc',$ns)){
    $offset=0
    foreach($run in $cell.SelectNodes('w:p/w:r',$ns)){
     $text=($run.SelectNodes('w:t',$ns)|ForEach-Object{$_.InnerText}) -join ''
     if(-not $text.Length){continue}
     $italicNode=$run.SelectSingleNode('w:rPr/w:i',$ns)
     $italic=$null -ne $italicNode -and $italicNode.GetAttribute('val',$ns.LookupNamespace('w')) -notin @('0','false','off')
     $positionNode=$run.SelectSingleNode('w:rPr/w:vertAlign',$ns)
     $position=if($positionNode){$positionNode.GetAttribute('val',$ns.LookupNamespace('w'))}else{'baseline'}
     $runs.Add([ordered]@{tableIndex=$ti;rowIndex=$ri;cellIndex=$ci;start=$offset;text=$text;italic=$italic;position=$position})
     $offset+=$text.Length
    }
    $vm=$cell.SelectSingleNode('w:tcPr/w:vMerge',$ns)
    if($vm -and $vm.GetAttribute('val',$ns.LookupNamespace('w')) -ne 'restart'){
     if($offset){throw 'Nonempty vertical continuation requires manual structural mapping'}
     $merges.Add([ordered]@{tableIndex=$ti;rowIndex=$ri;cellIndex=$ci;intoRow=$ri-1;intoCell=$ci})
    }
    $ci++
   }
   $ri++
  }
  $ti++
 }
 [IO.File]::WriteAllText($OutputPath,([ordered]@{sourceSHA256=(Get-FileHash -LiteralPath $SourceDocx -Algorithm SHA256).Hash;tableTextRuns=@($runs);mergedEmptyCells=@($merges)}|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
}finally{$zip.Dispose()}
