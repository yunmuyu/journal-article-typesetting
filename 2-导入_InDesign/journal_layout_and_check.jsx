#target indesign
(function(){
 var root=File($.fileName).parent,gate=File(root.fsName+'/journal_prepreview_gate.jsxinc'),bottom=File(root.fsName+'/journal_bottom_plan.jsxinc'),lib=File(root.fsName+'/journal_layout_rules.jsxinc');
 if(!gate.exists||!bottom.exists||!lib.exists)throw Error('缺少共享模块，请重新部署。');$.evalFile(gate);$.evalFile(bottom);$.evalFile(lib);
 var file=File.openDialog('选择文章排版检查配置JSON','JSON:*.json');if(!file)return;
 file.encoding='UTF-8';if(!file.open('r'))throw Error('配置无法读取');var raw=file.read();file.close();var cfg=eval('('+raw+')');
 if(cfg.sourceLogicalArticle){var logicalFile=File(cfg.sourceLogicalArticle);logicalFile.encoding='UTF-8';if(!logicalFile.open('r'))throw Error('原稿结构文件无法读取');var logical=eval('('+logicalFile.read()+')');logicalFile.close();cfg.sourceTextFormatting=logical.blocks;}
 var doc=app.open(File(cfg.documentPath));
 var result=JournalLayout.run(doc,cfg,true);doc.save();
 if(result.errors.length){var lines=[];for(var i=0;i<result.errors.length;i++)lines.push(result.errors[i].code+': '+result.errors[i].detail);alert('排版检查未通过：\n'+lines.join('\n')+'\n完整原文对照请运行Invoke-JournalLayout.ps1。');}
 else alert('版面规则检查通过。完整原文对照尚需运行Invoke-JournalLayout.ps1，不能仅据此交付。');
})();