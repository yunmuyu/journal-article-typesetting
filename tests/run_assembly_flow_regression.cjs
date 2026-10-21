const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const modulePath = path.resolve(__dirname, '../2-导入_InDesign/journal_article_assembly.jsxinc');
const source = fs.readFileSync(modulePath, 'utf8');
const context = vm.createContext({StartParagraph:{ANYWHERE:'anywhere'},Justification:{LEFT_ALIGN:'left'}});
vm.runInContext(source, context);
const assembly = context.JournalArticleAssembly;
const data = {blocks:[
  {role:'body',text:'先说明第一张图。'},
  {role:'figure_caption',text:'图1  测试图'},
  {role:'body',text:'完整介绍组合图。'},
  {role:'body',text:'组合图之后的文字。'},
  {role:'figure_caption',text:'图2  测试图二'},
  {role:'heading1',text:'4  应用'}
]};
const prepared = assembly.prepareBlocks(data,[{numbers:[1,2],afterParagraphText:'完整介绍组合图。'}]);
assert.deepEqual(Array.from(prepared.blocks, b=>b.text),['先说明第一张图。','完整介绍组合图。','JOURNAL_PANEL_0','组合图之后的文字。','4  应用']);
assert.equal(prepared.blocks[3].originalIndex,3);
assert.equal(prepared.captions[2],'图2  测试图二');
assert.throws(()=>assembly.prepareBlocks(data,[{numbers:[1],afterParagraphText:'没有这段'}]),/PANEL_ANCHOR/);
assert.equal(assembly.codeLine("import http from 'module';"),true);
assert.equal(assembly.codeLine('这是一段正文。'),false);
for(const line of [
  ' // 1. 动态注入鉴权凭证', ' * 全局请求封装方法', '# 后端核心登录接口',
  "return jsonify({'message': '参数不完整'})", '    try:', 'def login():',
  "'user_id': user['id'],", "}, PRIVATE_KEY, algorithm='RS256') # 私钥签名"
])assert.equal(assembly.codeLine(line),true,line);
for(const line of ['代码核心实现原理解析：','PMSM采用矢量控制。','1）防注入的数据读取。'])assert.equal(assembly.codeLine(line),false,line);
const stops=[],target={tabStops:{everyItem(){return {remove(){stops.length=0;}};},add(s){stops.push(s);}}};
assembly.setFormulaTabs(target,[{position:42.6,alignment:1},{position:69.1,alignment:2},{position:164.5,alignment:3}]);
assert.deepEqual(stops.map(s=>[s.position,s.alignment]),[[42.6,1],[69.1,2],[164.5,3]],'preserve every template stop and its alignment');
let range;
assembly.clearPayload({characters:{length:6,itemByRange:(a,b)=>({remove(){range=[a,b];}})}});
assert.deepEqual(range,[0,4],'the paragraph return must survive marker removal');
const caption={},anchor={startParagraph:'next-column'};
assembly.setTableBreak(caption,anchor,'next-column');
assert.equal(caption.startParagraph,'next-column');
assert.equal(caption.keepWithNext,1);
assert.equal(anchor.startParagraph,'anywhere','table cannot strand its caption');
assert(source.indexOf('JournalLayout.applyTypography(d,audit)') < source.indexOf('result.panels.push(placePanel'), 'measure after final typography');
assert(!/activeDocument|app\.select\(|paragraphAdjustments\[[^\]]/.test(source));
console.log('PASS semantic panel anchors, paragraph boundary, table caption break, phase order');
