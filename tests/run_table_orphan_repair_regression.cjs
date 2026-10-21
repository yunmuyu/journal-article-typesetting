const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const context=vm.createContext({Position:{NORMAL:0,SUPERSCRIPT:1}});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../2-导入_InDesign/journal_layout_rules.jsxinc'),'utf8'),context);
const text='测试内容',chars=[...text].map((contents,index)=>({contents,index,position:0,noBreak:false}));
function line(start,end){return {contents:text.slice(start,end),insertionPoints:[{index:start}],characters:{everyItem:()=>({getElements:()=>chars.slice(start,end)})}};}
const selected=[],cellText={lines:[line(0,3),line(3,4)]};
cellText.characters={itemByRange(start,end){return {set noBreak(value){selected.push({start,end,value});for(let i=start;i<=end;i++)chars[i].noBreak=value;}};}};
chars.forEach((character,index)=>cellText.characters[index]=character);
const table={label:'source-table-0',cells:[{texts:[cellText]}]},story={extractLabel:()=> 'body',paragraphs:[],tables:[table]};
const document={stories:[story],recompose(){cellText.lines=[line(0,2),line(2,4)];}};
assert.equal(context.JournalLayout.repairOrphans(document),1);
assert.deepEqual(selected,[{start:2,end:3,value:true}]);
assert.equal(context.JournalLayout.orphanLine(cellText.lines[1]),false);
chars.forEach(character=>character.noBreak=false);
cellText.lines=[line(0,3),line(3,4)];table.cells[0].overflows=true;
assert.equal(context.JournalLayout.repairOrphans(document),0);
assert.ok(chars.every(character=>character.noBreak===false),'a repair that causes overflow restores the original break permissions');
console.log('PASS table orphan repair binds the trailing CJK character to its preceding character without editing text');
