// Load journal_scoped_assembly.jsxinc before this fixture. Only this temporary
// document is closed; existing documents and the application remain open.
(function(){
    var document=null;
    try{
        document=app.documents.add();
        var group=document.paragraphStyleGroups.add({name:'candidate-heading-test'});
        var first=group.paragraphStyles.add({name:'一级标题',pointSize:12}).getElements()[0],firstId=first.id;
        var second=group.paragraphStyles.add({name:'二级标题',pointSize:10.5}).getElements()[0],secondId=second.id;
        var frame=document.pages[0].textFrames.add({geometricBounds:[20,20,100,150],
            contents:'0 引言'+String.fromCharCode(13)+'1.1 小节'}).getElements()[0];
        frame.parentStory.paragraphs.everyItem().applyParagraphStyle(second,true);
        var source=[{role:'heading1',text:'0 引言'},{role:'heading2',text:'1.1 小节'}];
        var changed=JournalScopedAssembly.restoreSourceHeadings(document,frame.parentStory,source);
        document.recompose();
        if(changed!==1||frame.paragraphs[0].appliedParagraphStyle.id!==firstId||
            frame.paragraphs[0].pointSize!==12||frame.paragraphs[1].appliedParagraphStyle.id!==secondId)
            throw Error('NATIVE_HEADING_ASSERT');
        if(JournalScopedAssembly.restoreSourceHeadings(document,frame.parentStory,source)!==0)
            throw Error('NATIVE_HEADING_IDEMPOTENCE');
        return 'PASS native InDesign heading restoration and idempotence';
    }finally{if(document&&document.isValid)document.close(SaveOptions.NO);}
}());
