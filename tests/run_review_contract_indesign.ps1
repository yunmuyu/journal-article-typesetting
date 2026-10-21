param()
$ErrorActionPreference='Stop'
$root=Join-Path (Split-Path $PSScriptRoot) '2-导入_InDesign'
$code=(@('journal_layout_rules.jsxinc','journal_frontmatter.jsxinc','journal_article_assembly.jsxinc','journal_layout_measurement.jsxinc','journal_reflow.jsxinc')|ForEach-Object{[IO.File]::ReadAllText((Join-Path $root $_),[Text.Encoding]::UTF8)}) -join "`n"
$code+=@'
(function(){
 function check(value,name){if(!value)throw Error('REVIEW_NATIVE_REGRESSION '+name);}
 check(JournalLayout.formulaPlacementAllowed({kind:'figure'},{}),'original figures remain allowed');
 check(!JournalLayout.formulaPlacementAllowed({kind:'formula'},{}),'PDF formulas blocked by default');
 check(JournalLayout.formulaPlacementAllowed({kind:'formula',placement:'native-vector'},{}),'native formulas allowed');
 check(JournalLayout.sourceProjection('f ⟦EQ-003⟧ φ_i').text==='fφ_i','formula markers preserve source offsets');
 check(JournalFrontmatter.englishStyleContract('enAffiliation',{leading:25,spaceBefore:0,spaceAfter:0}).leading===15,'unit leading');
 check(JournalFrontmatter.englishStyleContract('enTitle',{leading:22,spaceBefore:0,spaceAfter:0}).leading===22,'title style leading');
 check(JournalArticleAssembly.printedFormulaNumber({},17)===null,'unnumbered source');
 check(JournalArticleAssembly.printedFormulaNumber({displayNumbers:{17:'3'}},17)==='3','explicit source number');
 check(JournalLayout.removableHeadingBlank('\r',15,0,0,'h1'),'remove body-level empty paragraph');
 check(!JournalLayout.removableHeadingBlank('\r',.1,0,0,'h1'),'preserve panel marker');
 return 'PASS InDesign-native shared review contracts';
})();
'@
$app=New-Object -ComObject InDesign.Application.2020
$result=[string]$app.DoScript($code,1246973031)
if($result -ne 'PASS InDesign-native shared review contracts'){throw $result}
$result
