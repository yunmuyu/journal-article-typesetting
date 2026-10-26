function Get-NumberingValue($node,[string]$name,[string]$default){
 $found=$node.SelectSingleNode('w:'+$name,$script:numberNs)
 if($null -eq $found){return $default};return $found.GetAttribute('val',$script:wordNamespace)
}
function Initialize-WordNumbering([string]$xml,[string]$stylesXml=''){
 $script:wordNamespace='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
 $script:numberRoot=New-Object Xml.XmlDocument
 if($xml){$script:numberRoot.LoadXml($xml)}else{$script:numberRoot.LoadXml('<empty/>')}
 $script:numberNs=New-Object Xml.XmlNamespaceManager($script:numberRoot.NameTable)
 $script:numberNs.AddNamespace('w',$script:wordNamespace);$script:numberCounters=@{}
 $script:numberStyles=New-Object Xml.XmlDocument;if($stylesXml){$script:numberStyles.LoadXml($stylesXml)}else{$script:numberStyles.LoadXml('<empty/>')}
}
function Get-WordNumberPrefix($paragraph,$paragraphNs){
 $props=$paragraph.SelectSingleNode('w:pPr/w:numPr',$paragraphNs)
 if($null -eq $props){
  $styleNode=$paragraph.SelectSingleNode('w:pPr/w:pStyle',$paragraphNs);$styleId='';if($styleNode){$styleId=$styleNode.GetAttribute('val',$script:wordNamespace)}
  $seen=@{};while($styleId -and !$seen.ContainsKey($styleId)){$seen[$styleId]=$true;$style=$script:numberStyles.SelectSingleNode("//w:style[@w:styleId='$styleId']",$script:numberNs);if(!$style){break};$props=$style.SelectSingleNode('w:pPr/w:numPr',$script:numberNs);if($props){break};$styleId=Get-NumberingValue $style 'basedOn' ''}
  if($null -eq $props){return ''}
 }
 $identity=Get-NumberingValue $props 'numId' '0';if($identity -eq '0'){return ''}
 $level=[int](Get-NumberingValue $props 'ilvl' '0')
 $instance=$script:numberRoot.SelectSingleNode("//w:num[@w:numId='$identity']",$script:numberNs)
 if(!$instance){throw 'NUMBERING_INSTANCE_MISSING'}
 $abstract=Get-NumberingValue $instance 'abstractNumId' ''
 $definition=$script:numberRoot.SelectSingleNode("//w:abstractNum[@w:abstractNumId='$abstract']",$script:numberNs)
 if(!$definition){throw 'NUMBERING_DEFINITION_MISSING'}
 $levels=@{};foreach($n in $definition.SelectNodes('w:lvl',$script:numberNs)){$levels[[int]$n.GetAttribute('ilvl',$script:wordNamespace)]=$n}
 foreach($override in $instance.SelectNodes('w:lvlOverride',$script:numberNs)){
  $n=$override.SelectSingleNode('w:lvl',$script:numberNs);if($n){$levels[[int]$override.GetAttribute('ilvl',$script:wordNamespace)]=$n}
 }
 $current=$levels[$level];if(!$current){throw 'NUMBERING_LEVEL_MISSING'}
 if((Get-NumberingValue $current 'numFmt' '') -ne 'decimal' -or $current.SelectSingleNode('w:lvlRestart',$script:numberNs)){throw 'NUMBERING_FORMAT_OR_RESTART_UNSUPPORTED'}
 if(!$script:numberCounters.ContainsKey($identity)){$script:numberCounters[$identity]=@{}}
 $counters=$script:numberCounters[$identity];$start=[int](Get-NumberingValue $current 'start' '1')
 foreach($override in $instance.SelectNodes('w:lvlOverride',$script:numberNs)){if([int]$override.GetAttribute('ilvl',$script:wordNamespace) -eq $level){$start=[int](Get-NumberingValue $override 'startOverride' ([string]$start))}}
 if($counters.ContainsKey($level)){$counters[$level]++}else{$counters[$level]=$start}
 foreach($key in @($counters.Keys)){if($key -gt $level){$counters.Remove($key)}}
 $template=Get-NumberingValue $current 'lvlText' ''
 $label=[regex]::Replace($template,'%([1-9])',{param($match)
  $index=[int]$match.Groups[1].Value-1
  if(!$levels.ContainsKey($index) -or (Get-NumberingValue $levels[$index] 'numFmt' '') -ne 'decimal'){throw 'NUMBERING_PLACEHOLDER_UNSUPPORTED'}
  if($counters.ContainsKey($index)){return [string]$counters[$index]};return (Get-NumberingValue $levels[$index] 'start' '1')
 })
 if(!$label){throw 'NUMBERING_LABEL_EMPTY'};return $label+' '
}
