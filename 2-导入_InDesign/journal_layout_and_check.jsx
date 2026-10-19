#target indesign
(function(){
 var root=File($.fileName).parent,lib=File(root.fsName+'/journal_layout_rules.jsxinc');
 if(!lib.exists)throw Error('缺少journal_layout_rules.jsxinc，请重新部署。');$.evalFile(lib);
 var file=File.openDialog('选择文章排版检查配置JSON','JSON:*.json');if(!file)return;
 file.encoding='UTF-8';if(!file.open('r'))throw Error('配置无法读取');var raw=file.read();file.close();var cfg=eval('('+raw+')');
 var doc=app.open(File(cfg.documentPath));
 var result=JournalLayout.run(doc,cfg,true);doc.save();
 if(result.errors.length){var lines=[];for(var i=0;i<result.errors.length;i++)lines.push(result.errors[i].code+': '+result.errors[i].detail);alert('排版检查未通过：\n'+lines.join('\n')+'\n完整原文对照请运行Invoke-JournalLayout.ps1。');}
 else alert('版面规则检查通过。完整原文对照尚需运行Invoke-JournalLayout.ps1，不能仅据此交付。');
})();