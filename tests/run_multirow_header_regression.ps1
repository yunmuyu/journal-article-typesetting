param([Parameter(Mandatory=$true)][string]$ConfigPath,[Parameter(Mandatory=$true)][string]$ScratchDirectory)
$ErrorActionPreference='Stop'
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
[void][IO.Directory]::CreateDirectory($ScratchDirectory)
$copy=Join-Path $ScratchDirectory 'multirow-header_QA.indd'
[IO.File]::Copy($config.documentPath,$copy,$true)
$config.documentPath=$copy.Replace('\','/')
$config|Add-Member -NotePropertyName tableHeaderRows -NotePropertyValue @(2,2,2) -Force
$json=ConvertTo-Json -InputObject $config -Depth 20 -Compress
$module=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\2-导入_InDesign\journal_layout_rules.jsxinc'))
$script=$module+@"
(function(){var d=app.open(File($json.documentPath));var c=$json;try{JournalLayout.bind(d,c);var body=d.stories.itemByID(c.bindings[0].id);for(var ti=0;ti<body.tables.length;ti++)body.tables[ti].rows[1].rowType=RowTypes.HEADER_ROW;var rowCount=body.tables[0].rows.length;var result=JournalLayout.audit(d,c);for(var i=0;i<result.errors.length;i++)if(result.errors[i].code==='TABLE_HEADER')throw Error('Two real header rows were rejected');JournalLayout.applyTypography(d,c);if(body.tables[0].rows.length!==rowCount||body.tables[0].headerRowCount!==2)throw Error('Header normalization changed real rows');c.tableHeaderRows[0]=1;var negative=JournalLayout.audit(d,c),blocked=false;for(var i=0;i<negative.errors.length;i++)if(negative.errors[i].code==='TABLE_HEADER')blocked=true;if(!blocked)throw Error('Wrong header count was not blocked');return 'PASS multirow real header accepted, row count preserved, mismatch blocked';}catch(e){return 'FAIL '+e;}finally{d.close(SaveOptions.NO);}})();
"@
$app=New-Object -ComObject InDesign.Application.2020
$result=$app.DoScript($script,1246973031)
$result
if($result -notlike 'PASS*'){throw $result}
