param(
    [Parameter(Mandatory=$true)][string]$SourceIdml,
    [Parameter(Mandatory=$true)][string]$DestinationIdml
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
$source=(Get-Item -LiteralPath $SourceIdml).FullName
$destination=[IO.Path]::GetFullPath($DestinationIdml)
if([IO.Path]::GetExtension($source) -ne '.idml' -or [IO.Path]::GetExtension($destination) -ne '.idml'){throw 'IDML files required'}
if($source -eq $destination -or (Test-Path -LiteralPath $destination)){throw 'Destination must be a new test copy'}
$archive=[IO.Compression.ZipFile]::OpenRead($source)
try {
    $fontsEntry=$archive.GetEntry('Resources/Fonts.xml')
    if(-not $fontsEntry){throw 'IDML font resources missing'}
    $reader=[IO.StreamReader]::new($fontsEntry.Open())
    try {[xml]$fonts=$reader.ReadToEnd()}finally{$reader.Dispose()}
    $installed=@($fonts.SelectNodes('//FontFamily[@Name="Times New Roman"]/Font[@FontStyleName="Regular" and @Status="Installed"]'))
    if($installed.Count -ne 1){throw 'An installed regular Times New Roman resource is required'}
    $pending=[Collections.Generic.List[object]]::new()
    $references=0;$removed=0
    foreach($entry in $archive.Entries){
        $stream=$entry.Open();$buffer=[IO.MemoryStream]::new()
        try {$stream.CopyTo($buffer);$bytes=$buffer.ToArray()}finally{$stream.Dispose();$buffer.Dispose()}
        if($entry.FullName.EndsWith('.xml')){
            $xml=[xml]::new();$xml.PreserveWhitespace=$true
            $xml.LoadXml([Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF))
            $changed=$false
            foreach($node in @($xml.SelectNodes('//AppliedFont[text()="Times New Roman (OTF)"]'))){$node.InnerText='Times New Roman';$references++;$changed=$true}
            if($entry.FullName -eq 'Resources/Fonts.xml'){
                foreach($node in @($xml.SelectNodes('//FontFamily[@Name="Times New Roman (OTF)"]'))){[void]$node.ParentNode.RemoveChild($node);$removed++;$changed=$true}
            }
            if($changed){$bytes=[Text.UTF8Encoding]::new($false).GetBytes($xml.OuterXml)}
        }
        $pending.Add(@{Name=$entry.FullName;Bytes=$bytes})
    }
}finally{$archive.Dispose()}
$output=[IO.Compression.ZipFile]::Open($destination,[IO.Compression.ZipArchiveMode]::Create)
try {foreach($item in $pending){$entry=$output.CreateEntry($item.Name);$stream=$entry.Open();try{$stream.Write($item.Bytes,0,$item.Bytes.Length)}finally{$stream.Dispose()}}}finally{$output.Dispose()}
[ordered]@{source=$source;destination=$destination;referencesRepaired=$references;obsoleteFamiliesRemoved=$removed}|ConvertTo-Json
