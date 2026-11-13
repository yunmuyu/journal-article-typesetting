const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const context=vm.createContext({FontStatus:{INSTALLED:1},Position:{SUPERSCRIPT:2,SUBSCRIPT:3}});
vm.runInContext(fs.readFileSync(require('node:path').join(__dirname,'../2-导入_InDesign/journal_frontmatter.jsxinc'),'utf8'),context);
function character(contents, reject=false){return {contents,pointSize:9,leading:13,position:0,fontStyle:'Regular',appliedFont:{name:'SimSun\tRegular'},set properties(v){this.fontStyle=v.fontStyle;this.appliedFont={name:(reject?'Times New Roman (OTF)':v.appliedFont)+'\t'+v.fontStyle,status:1};}};}
const chars=[character('α'),character('、'),character('x'),character('2')];
chars.itemByRange=(a,b)=>({set position(value){for(let i=a;i<=b;i++)chars[i].position=value;}});
context.JournalFrontmatter.applySourceRuns({characters:chars},[{start:0,end:3,italic:true},{start:3,end:4,position:'subscript'}]);
assert.equal(chars[0].fontStyle,'Italic');assert.equal(chars[2].fontStyle,'Italic');
assert.equal(chars[1].fontStyle,'Regular');assert.equal(chars[3].position,3);
for(const c of chars){assert.equal(c.pointSize,9);assert.equal(c.leading,13);}
chars[0]=character('α',true);
assert.throws(()=>context.JournalFrontmatter.applySourceRuns({characters:chars},[{start:0,end:1,italic:true}]),/FRONTMATTER_SOURCE_FONT/);
console.log('PASS abstract source italic, upright punctuation, subscript, size/leading and stale-font rejection');
