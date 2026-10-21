const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(require('node:path').join(__dirname,'../2-导入_InDesign/seed_issue_article_pages.jsx'),'utf8');
const removed=[];
const footer={constructor:{name:'TextFrame'},parentStory:{paragraphs:[{appliedParagraphStyle:{name:'收稿日期'}}]}};
const top={constructor:{name:'TextFrame'}};
const group={constructor:{name:'Group'},allPageItems:[footer],remove(){removed.push('footer');}};
const figure={constructor:{name:'Group'},allPageItems:[],remove(){removed.push('figure');}};
const page={allPageItems:[top,group,footer,figure],pageItems:{everyItem(){return {getElements(){return [top,group,figure];}};}}};
const start=source.indexOf('// Remove payload');
const end=source.indexOf('// Clear each distinct story');
assert.ok(start>=0&&end>start);
const context=vm.createContext({created:[page],d:{recompose(){}}});
for(const name of ['allTextFrames','keepReceivedGroup']){
 const i=source.indexOf('function '+name+'(');if(i<0)continue;
 const brace=source.indexOf('{',i);let level=1,j=brace+1;
 for(;j<source.length&&level;j++){if(source[j]==='{')level++;if(source[j]==='}')level--;}
 vm.runInContext(source.slice(i,j),context);
}
vm.runInContext(source.slice(start,end),context);
assert.deepEqual(removed,['figure'],'Keep the native received-date group while removing figure payload');
assert.equal(vm.runInContext('allTextFrames(created[0]).length',context),2,'Grouped footer must participate in story discovery');
console.log('PASS native received-date group survives payload cleanup and its frame is discoverable');
