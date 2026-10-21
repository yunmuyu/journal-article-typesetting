Set-StrictMode -Version Latest
function New-JournalCharacterDefinitionEvidence {
    param([Parameter(Mandatory)]$Application,[Parameter(Mandatory)][int]$SourceId,[Parameter(Mandatory)][int]$TargetId,[Parameter(Mandatory)][int]$AuthorityId,[Parameter(Mandatory)][string]$Directory)
    $repo=$PSScriptRoot
    $prefix=Join-Path $Directory ('character-definition-'+[guid]::NewGuid().ToString('N'))
    $spec=@{source=$SourceId;target=$TargetId;authority=$AuthorityId;sourceExport="$prefix-source.idml";authorityExport="$prefix-authority.idml"}|ConvertTo-Json -Compress
    $code=[IO.File]::ReadAllText("$repo/journal_regression_snapshot.jsxinc")+[IO.File]::ReadAllText("$repo/journal_merge_safety.jsxinc")+"var DefinitionProbe=$spec;"+@'
(function(p){try{var s=app.documents.itemByID(p.source),t=app.documents.itemByID(p.target),r=app.documents.itemByID(p.authority);if(!/(QA|copy|副本)/i.test(s.name)||!/(QA|copy|副本)/i.test(t.name))throw Error('QA_REQUIRED');if(JournalMergeSafety.characterStyleConflicts(t,r).length)throw Error('TARGET_NOT_AUTHORITATIVE');var names=JournalMergeSafety.characterStyleConflicts(s,t),pairs=[];
function path(st){var parts=[st.name],parent=st.parent;while(parent&&parent.constructor.name==='CharacterStyleGroup'){parts.unshift(parent.name);parent=parent.parent;}return parts.join('/');}function find(d,n){var a=d.allCharacterStyles;for(var i=0;i<a.length;i++)if(path(a[i])===n)return a[i];throw Error('STYLE_MISSING '+n);}
for(var i=0;i<names.length;i++){var a=find(s,names[i]),b=find(t,names[i]);var af=String(a.appliedFont),sc=s.compositeFonts.itemByName(af),tc=t.compositeFonts.itemByName(af);if(sc.isValid!==false||tc.isValid!==false){if(sc.isValid===false||tc.isValid===false||sc.compositeFontEntries.length!==tc.compositeFontEntries.length)throw Error('COMPOSITE_FONT_MISMATCH '+af);for(var j=0;j<sc.compositeFontEntries.length;j++)if(sc.compositeFontEntries[j].name!==tc.compositeFontEntries[j].name||JournalMergeSafety.characterStyleSignature(sc.compositeFontEntries[j])!==JournalMergeSafety.characterStyleSignature(tc.compositeFontEntries[j]))throw Error('COMPOSITE_ENTRY_MISMATCH '+af);}
pairs.push({name:names[i],sourceId:a.id,targetId:b.id,sourceSignature:JournalMergeSafety.characterStyleSignature(a),targetSignature:JournalMergeSafety.characterStyleSignature(b)});}
if(pairs.length){s.exportFile(ExportFormat.INDESIGN_MARKUP,File(p.sourceExport),false);r.exportFile(ExportFormat.INDESIGN_MARKUP,File(p.authorityExport),false);}return JournalRegressionSnapshot.json({source:s.id,target:t.id,sourcePath:s.fullName.fsName,targetPath:t.fullName.fsName,pairs:pairs});}catch(e){return 'ERROR '+e+' LINE '+e.line;}})(DefinitionProbe);
'@
    $raw=[string](Invoke-JournalInDesignScript -Application $Application -Code $code)
    if($raw.StartsWith('ERROR')){throw $raw}
    $probe=$raw|ConvertFrom-Json
    function Read-StyleDefinitions([string]$Path){
        $zip=[IO.Compression.ZipFile]::OpenRead($Path)
        try{$reader=[IO.StreamReader]::new($zip.GetEntry('Resources/Styles.xml').Open());try{[xml]$xml=$reader.ReadToEnd()}finally{$reader.Dispose()}}finally{$zip.Dispose()}
        $styles=@{}
        foreach($node in $xml.SelectNodes('//CharacterStyle')){
            $parts=[Collections.Generic.List[string]]::new();$parts.Insert(0,$node.GetAttribute('Name'));$parent=$node.ParentNode
            while($parent -and $parent.LocalName -eq 'CharacterStyleGroup'){$parts.Insert(0,$parent.GetAttribute('Name'));$parent=$parent.ParentNode}
            $clone=$node.CloneNode($true)
            foreach($attr in @('Self','StyleUniqueId','Imported')){$clone.RemoveAttribute($attr)}
            $styles[($parts -join '/')]=$clone.OuterXml
        }
        return $styles
    }
    if($probe.pairs.Count){$a=Read-StyleDefinitions "$prefix-source.idml";$b=Read-StyleDefinitions "$prefix-authority.idml"
        foreach($pair in $probe.pairs){if(-not $a.ContainsKey($pair.name) -or -not $b.ContainsKey($pair.name) -or $a[$pair.name] -cne $b[$pair.name]){throw "CHARACTER_RAW_DEFINITION_MISMATCH $($pair.name)"};$pair|Add-Member sourceDefinition $a[$pair.name];$pair|Add-Member targetDefinition $b[$pair.name]}
    }
    $json=$probe|ConvertTo-Json -Depth 30 -Compress
    [IO.File]::WriteAllText("$prefix.json",$json,[Text.UTF8Encoding]::new($false))
    return 'var CharacterDefinitionProof='+$json+';'+@'
(function(p){var s=app.documents.itemByID(p.source),t=app.documents.itemByID(p.target);if(s.fullName.fsName!==File(p.sourcePath).fsName||t.fullName.fsName!==File(p.targetPath).fsName)throw Error('CHARACTER_EVIDENCE_PATH_CHANGED');for(var i=0;i<p.pairs.length;i++){var e=p.pairs[i];JournalMergeSafety.registerCharacterDefinitionEvidence(s.characterStyles.itemByID(e.sourceId),t.characterStyles.itemByID(e.targetId),e);}})(CharacterDefinitionProof);
'@
}
Export-ModuleMember -Function New-JournalCharacterDefinitionEvidence
