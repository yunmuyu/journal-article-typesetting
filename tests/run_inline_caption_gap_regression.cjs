const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const ctx=vm.createContext({Justification:{RIGHT_ALIGN:2,LEFT_JUSTIFIED:1},SpecialCharacters:{ELLIPSIS_CHARACTER:9}});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_layout_rules.jsxinc'),'utf8'),ctx);
function p(text,leading=14,style='图注/表名') {return {contents:text,leading,pointSize:9,appliedParagraphStyle:{name:style},
 allPageItems:[],tables:[],lines:[],spaceBefore:0,spaceAfter:0,characters:{everyItem:()=>({getElements:()=>[]})}};}
const paragraphs=[],items=[];
function group(label,caption,gapPt){const anchor=p('\uFFFC\r'),gap=p('\r',gapPt),cap=p(caption+'\r');
 const object={label,allGraphics:[{}],parent:{constructor:{name:'Character'},paragraphs:[anchor]}};
 anchor.allPageItems=[object];items.push(object);paragraphs.push(anchor,gap,cap);return {anchor,gap,cap};}
const main=group('source-figure-1','图1  合成图',5),sub=group('external-image','（a）合成子图',2);
const ordinary=[p('正文\r'),p('\r',10),p('（b）无图的普通文字\r')];paragraphs.push(...ordinary);
const formula=group('source-formula-1','（c）不是图片图注',2);formula.anchor.allPageItems[0].allGraphics=[];items.pop();
const story={id:1,paragraphs,tables:[],extractLabel:()=> 'body'},d={stories:[story],allPageItems:items,allParagraphStyles:[],recompose(){}};
// The public typography entry point must normalize individually anchored subcaptions too.
ctx.JournalLayout.applyTypography(d,{});
assert.equal(sub.gap.leading,5,'an unrecognized image label must not let a local 2pt override survive');
assert.equal(main.gap.leading,5);assert.equal(ordinary[1].leading,10);assert.equal(formula.gap.leading,2);
sub.gap.leading=2;
let found=ctx.JournalLayout.inlineCaptionSpacing(d,false);
assert.equal(found.length,1);assert.match(found[0],/actual=2/);assert.equal(sub.gap.leading,2);
ctx.JournalLayout.inlineCaptionSpacing(d,true);ctx.JournalLayout.inlineCaptionSpacing(d,true);
assert.equal(sub.gap.leading,5);assert.equal(ctx.JournalLayout.inlineCaptionSpacing(d,false).length,0);
sub.cap.spaceBefore=1;assert.equal(ctx.JournalLayout.inlineCaptionSpacing(d,false).length,1,'additive local spacing is detected');
ctx.JournalLayout.inlineCaptionSpacing(d,true);assert.equal(sub.cap.spaceBefore,0);
assert.throws(()=>ctx.JournalLayout.applyTypography(d,{figureCaptionGapPt:2}),/FIGURE_CAPTION_GAP_CONTRACT/);
assert.equal(ctx.JournalLayout.captionGapContract({figureCaptionGapPt:5}),5);
console.log('PASS fixed 5pt main/subcaption gap, local override detection, idempotency, formula and unrelated spacing protection');
