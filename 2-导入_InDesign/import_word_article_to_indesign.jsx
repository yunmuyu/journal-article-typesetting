#target indesign
(function () {
    var CONFIG = {
        paragraphStyles: {
            received_date: ["开头部分/收稿日期", "开头部分/基金项目", "正文/正文", "正文"],
            fund: ["开头部分/基金项目", "正文/正文", "正文"],
            cn_title: ["开头部分/大标题", "大标题"], cn_author: ["开头部分/作者", "作者"], cn_affiliation: ["开头部分/作者单位", "作者单位"],
            cn_abstract: ["开头部分/中文摘要", "中文摘要", "摘要"], cn_keywords: ["开头部分/中文摘要", "关键词", "摘要"], classification: ["开头部分/中图分类号 文献标识码 文章编号", "中图分类号", "正文/正文", "正文"],
            en_title: ["开头部分/英语大标题", "开头部分/英文大标题", "英语大标题", "英文大标题"], en_author: ["开头部分/英语作者", "开头部分/英文作者", "英语作者", "英文作者"], en_affiliation: ["开头部分/英文作者单位", "英文作者单位"], en_abstract: ["开头部分/英文摘要", "英文摘要", "摘要"], en_keywords: ["开头部分/英文摘要", "英文关键词", "Keywords"],
            heading1: ["正文/一级标题", "一级标题"], heading2: ["正文/二级标题", "二级标题", "小标题"], body: ["正文/正文", "正文", "内文"], blank: ["正文/正文", "正文", "内文"], caption: ["正文/图注/表名", "图注/表名", "图题", "表题"], figure_caption: ["正文/图注/表名", "图注/表名", "图题"], table_caption: ["正文/图注/表名", "图注/表名", "表题"],
            table_row: ["正文/正文", "正文", "内文"], table_start: ["正文/图注/表名", "正文/正文", "正文"], table_end: ["正文/图注/表名", "正文/正文", "正文"], table_gap: ["正文/正文", "正文", "内文"], formula: ["公式", "正文/正文", "正文", "内文"], references_title: ["结尾/参考文献 标题", "参考文献 标题", "参考文献", "一级标题"], reference_item: ["结尾/参考文献 内容", "参考文献 内容", "参考文献", "正文/正文", "正文", "内文"], author_bio: ["结尾/作者简介", "作者简介标题", "作者简介", "正文/正文", "正文", "内文"]
        },
        characterStyles: { italic: ["斜体", "x", "变量", "英文斜体"], bold: ["黑体", "英文黑体", "12磅黑体"], sup: ["上标"], sub: ["下标"], authorBioLabel: ["12磅黑体", "作者简介黑体", "黑体", "复合黑体"] },
        disabledCharacterStyles: {},
        bodyRoles: { body:true, formula:true },   // 参考文献/作者简介不强制 10.5pt/现宋体，交给各自段落样式决定字号字体
        bodyFontNames: ["现 宋体-1", "现宋体-1", "现 宋体", "现宋体", "现 宋体-1-6"],
        fallbackItalicFontNames: ["Times New Roman\tItalic", "Times New Roman\t斜体", "TimesNewRomanPS-ItalicMT", "Times New Roman Italic"],
        fallbackBoldItalicFontNames: ["Times New Roman\tBold Italic", "Times New Roman Bold Italic", "TimesNewRomanPS-BoldItalicMT"],
        mathFontNames: ["Cambria Math", "Cambria Math\tRegular", "CambriaMath"],   // 数学符号 ∈ ∙ ⋯ × 等用 Cambria Math
        equalsFontNames: ["Symbol", "Symbol\tRegular", "Symbol\tMedium"],          // 等号 = 用 Symbol
        heitiFontNames: ["黑体", "SimHei", "Heiti SC", "Heiti TC", "STHeiti", "Microsoft YaHei"],   // ≤ ≥ ＜ ＞ 用黑体（不要现黑体）
        normalizeFullwidthEquals: true,                                            // 全角＝转半角=后再套 Symbol（用户确认）
        equalsSpaceSubscript: true,                                                // 等号前后各加一个下标空格
        kerningMethods: ["$ID/Metrics Roman only", "原始设定 - 仅罗马字"]            // 字偶间距：原始设定 - 仅罗马字
    };
    if (app.documents.length === 0) { alert("请先打开目标 InDesign 文档。"); return; }
    app.doScript(main, ScriptLanguage.JAVASCRIPT, [], UndoModes.ENTIRE_SCRIPT, "导入整篇 Word JSON");
    function main() {
        var doc = app.activeDocument, file = File.openDialog("选择由 docx_to_id_json.py 生成的 JSON 文件", "JSON:*.json"); if (!file) return;
        file.encoding = "UTF-8"; if (!file.open("r")) { alert("无法打开 JSON 文件。"); return; }
        var raw = file.read(); file.close(); var data = parseJSON(raw);
        if (!data || !data.blocks || !data.blocks.length) { alert("JSON 里没有可导入内容。"); return; }
        var target = getTargetInsertionPoint(doc); if (!target) { alert("请先把文字光标放到要导入的位置，或选中一个文本框。"); return; }
        var previousRedraw=app.scriptPreferences.enableRedraw;
        app.scriptPreferences.enableRedraw = false;
        try {
        var report = {inserted:0, missingPStyles:{}, italicFontFailed:0, boldItalicFontFailed:0, mathFixed:0, equalsFixed:0, heitiFixed:0, glyphNormalized:0, kerningApplied:false}, storyId=target.parentStory.id, insertionIndex=target.index;
        for (var i=0; i<data.blocks.length; i++) {
            var block = data.blocks[i], text = block.text || "", startIndex=insertionIndex, story=doc.stories.itemByID(storyId), insertion=story.insertionPoints[startIndex];
            insertion.contents = text + "\r";
            story = doc.stories.itemByID(storyId); var para = story.insertionPoints[startIndex].paragraphs[0];
            applyPStyle(doc, para, block.role, report);
            clearInheritedCharacterFormatting(doc, para);
            if (block.role === "table_gap") applyTableGap(para);
            normalizeParagraph(doc, para, block.role); applyRuns(doc, storyId, startIndex, block.runs || [], report);
            story = doc.stories.itemByID(storyId); para = story.insertionPoints[startIndex].paragraphs[0];
            if (block.role === "author_bio") applyAuthorBioLabel(doc, story, startIndex, text);
            if (block.role === "en_abstract" || block.role === "en_keywords") applyEnglishLabel(para);
            if (text.length > 0) {
                applyKerning(para, report);
                fixSpecialGlyphs(doc, para, report);
                story = doc.stories.itemByID(storyId); para = story.insertionPoints[startIndex].paragraphs[0]; insertionIndex = para.insertionPoints[-1].index;
            } else {
                insertionIndex = startIndex + 1;
            }
            report.inserted++;
        }
        doc.recompose(); alert(buildReport(doc, report, data.summary));
        } finally { app.scriptPreferences.enableRedraw=previousRedraw; }
    }
    function parseJSON(raw) { if (typeof JSON !== "undefined" && JSON.parse) return JSON.parse(raw); return eval("(" + raw + ")"); }
    function getTargetInsertionPoint(doc) { if (app.selection.length > 0) { var s=app.selection[0]; if (s.hasOwnProperty("insertionPoints")) return s.insertionPoints[0]; if (s instanceof TextFrame) return s.parentStory.insertionPoints[-1]; if (s.hasOwnProperty("parentStory")) return s.parentStory.insertionPoints[s.index]; } if (doc.stories.length > 0) return doc.stories[0].insertionPoints[-1]; return null; }
    function applyPStyle(doc, para, role, report) { var style = findParagraphStyle(doc, CONFIG.paragraphStyles[role] || CONFIG.paragraphStyles.body); if (style) para.applyParagraphStyle(style, true); else report.missingPStyles[role || "unknown"] = true; }
    function clearInheritedCharacterFormatting(doc, para) {
        try { para.characters.everyItem().applyCharacterStyle(doc.characterStyles[0], false); } catch(e) {}
        try { para.clearOverrides(OverrideType.CHARACTER_ONLY); } catch(e2) {}
    }
    function normalizeParagraph(doc, para, role) {
        if (role === "author_bio") {
            var kai=findInstalledFont(["楷体"]); if(!kai)throw Error("缺少作者简介字体：楷体");
            para.appliedFont=kai;para.pointSize=9;para.leading=13;para.spaceBefore=0;para.spaceAfter=0;return;
        }
        var english=role==="en_abstract"||role==="en_keywords";
        if (!CONFIG.bodyRoles[role] && !english) return;
        var bodyFont=findInstalledFont([CONFIG.bodyFontNames[0]]);
        if(!bodyFont)throw Error("缺少规定字体："+CONFIG.bodyFontNames[0]);
        para.pointSize=english?9:10.5;para.leading=english?13:15;
        para.characters.everyItem().appliedFont=bodyFont;
    }
    function applyRuns(doc, storyId, base, runs, report) {
        for (var i=0; i<runs.length; i++) {
            var r=runs[i], start=base+Number(r.start||0), end=base+Number(r.end||0)-1;
            if (end<start) continue;
            var story, chars;
            try { story=doc.stories.itemByID(storyId); chars=story.characters.itemByRange(start,end).getElements()[0]; } catch(e) { continue; }
            var scriptSize=chars.pointSize, scriptLeading=chars.leading;
            var nativeFaces=r.italic ? captureEastAsianFaces(chars) : [];
            var needsRomanItalic=nativeFaces.length < end-start+1;
            if (r.position==="superscript") {
                var sup=findCharacterStyle(doc,CONFIG.characterStyles.sup);
                applyCharacterStyleSafe(chars,sup);
            } else if (r.position==="subscript") {
                var sub=findCharacterStyle(doc,CONFIG.characterStyles.sub);
                applyCharacterStyleSafe(chars,sub);
            }
            if (r.italic && !r.bold) applyCharacterStyleSafe(chars,findCharacterStyle(doc,CONFIG.characterStyles.italic));
            else if (r.bold && !r.italic) applyCharacterStyleSafe(chars,findCharacterStyle(doc,CONFIG.characterStyles.bold));
            if (r.italic && r.bold && needsRomanItalic) {
                if (!applyBoldItalicFont(chars)) report.boldItalicFontFailed++;
            } else if (r.italic && needsRomanItalic) {
                if (!applyItalicFont(chars)) report.italicFontFailed++;
            } else if (r.bold && !r.italic) {
                try { chars.fontStyle="Bold"; } catch(e4) {}
            }
            story=doc.stories.itemByID(storyId); chars=story.characters.itemByRange(start,end).getElements()[0];
            restoreEastAsianFaces(doc,story,start,nativeFaces,r.bold);
            try { chars.pointSize=scriptSize; chars.leading=scriptLeading; } catch(e5) {}
            try {
                if (r.position==="superscript") chars.position=Position.SUPERSCRIPT;
                else if (r.position==="subscript") chars.position=Position.SUBSCRIPT;
                else chars.position=Position.NORMAL;
            } catch(e6) {}
        }
    }
    function isEastAsianPunctuation(code) {
        return (code>=0x3000 && code<=0x303F) || (code>=0xFE10 && code<=0xFE4F) || (code>=0xFF00 && code<=0xFF65);
    }
    function captureEastAsianFaces(chars) {
        var elements=getCharacterElements(chars), faces=[];
        for (var i=0;i<elements.length;i++) {
            var text=String(elements[i].contents), code=text.charCodeAt(0);
            if (isEastAsianPunctuation(code) || (code>=0x3400 && code<=0x9FFF) || (code>=0xF900 && code<=0xFAFF)) {
                faces.push({offset:i,font:elements[i].appliedFont,style:elements[i].fontStyle,skew:elements[i].skew,punctuation:isEastAsianPunctuation(code)});
            }
        }
        return faces;
    }
    function restoreEastAsianFaces(doc,story,start,faces,bold) {
        for (var i=0;i<faces.length;i++) {
            var face=faces[i], c=story.characters[start+face.offset];
            c.appliedFont=face.font; c.fontStyle=face.style;
            if (bold && !face.punctuation) applyCharacterStyleSafe(c,findCharacterStyle(doc,CONFIG.characterStyles.bold));
            c.skew=face.punctuation ? face.skew : 12;
        }
    }
    function applyCharacterStyleSafe(chars, style) {
        if (!style) return false;
        var styleName="";
        try { styleName=String(style.name); } catch(e0) {}
        if (styleName && CONFIG.disabledCharacterStyles[styleName]) return false;
        try {
            if (style.isValid === false) return false;
            chars.applyCharacterStyle(style,false);
            return true;
        } catch(e) {
            if (styleName) CONFIG.disabledCharacterStyles[styleName]=true;
            return false;
        }
    }
    function isParagraphStyle(style) { try { return style && style.isValid && style.reflect && String(style.reflect.name)==="ParagraphStyle"; } catch(e) { return false; } }
    function findParagraphStyle(doc,names) { for (var i=0;i<names.length;i++) { var s=getPStyleByPath(doc,names[i]); if (isParagraphStyle(s)) return s; } return null; }
    function getPStyleByPath(doc,path) { var parts=path.split("/"); if (parts.length>=2) { var g=doc.paragraphStyleGroups.itemByName(parts[0]); if (g.isValid) { var s=g.paragraphStyles.itemByName(parts.slice(1).join("/")); if (isParagraphStyle(s)) return s; } } var direct=doc.paragraphStyles.itemByName(path); if (isParagraphStyle(direct)) return direct; return findPStyleByKeyword(doc,parts[parts.length-1]); }
    function findPStyleByKeyword(doc,keyword) { for (var i=0;i<doc.paragraphStyles.length;i++) { var s=doc.paragraphStyles.item(i); if (isParagraphStyle(s) && s.name.indexOf(keyword)!==-1) return s; } for (var g=0;g<doc.paragraphStyleGroups.length;g++) { var group=doc.paragraphStyleGroups.item(g); for (var j=0;j<group.paragraphStyles.length;j++) { var gs=group.paragraphStyles.item(j); if (isParagraphStyle(gs) && gs.name.indexOf(keyword)!==-1) return gs; } } return null; }
    function findCharacterStyle(doc,names) { for (var i=0;i<names.length;i++) { var s=doc.characterStyles.itemByName(names[i]); if (s.isValid) return s; } for (var j=0;j<doc.characterStyles.length;j++) { var c=doc.characterStyles.item(j); for (var k=0;k<names.length;k++) if (c.name.indexOf(names[k])!==-1) return c; } return null; }
    // 只返回"真正已安装"的字体（status==INSTALLED）。⚠ 关键：itemByName 对一个文档里残留的
    // 缺失字体名也会返回 isValid==true 的对象（status==NOT_AVAILABLE），直接套上去就是粉红高亮的缺字。
    // 所以必须查 status，否则像 "Times New Roman\tBold Italic" 这种名可能命中缺失占位。
    function findInstalledFont(names) {
        for (var i=0;i<names.length;i++) {
            try { var f=app.fonts.itemByName(names[i]); if (f.isValid && f.status===FontStatus.INSTALLED) return f; } catch(e) {}
        }
        return null;
    }
    function applyItalicFont(chars) {
        var it=findInstalledFont(CONFIG.fallbackItalicFontNames);
        if (it) {
            try { chars.appliedFont=it; chars.fontStyle="Italic"; if (isInstalledTimesFace(chars,"Italic")) return true; } catch(e) {}
            if (replaceWithSeededTimes(chars,it,"Italic")) return true;
        }
        return isInstalledTimesFace(chars,"Italic");
    }
    function getCharacterElements(chars) {
        try {
            var elements=chars.characters.everyItem().getElements();
            if (elements && elements.length) return elements;
        } catch(e) {}
        try { return chars.getElements(); } catch(e2) {}
        return [];
    }
    function isInstalledTimesFace(chars, face) {
        var elements=getCharacterElements(chars);
        if (!elements.length) return false;
        for (var i=0;i<elements.length;i++) {
            try {
                var font=elements[i].appliedFont;
                if (font.status!==FontStatus.INSTALLED || String(font.fontFamily)!=="Times New Roman" || String(font.name).indexOf("(OTF)")!==-1 || String(elements[i].fontStyle)!==face) return false;
            } catch(e) { return false; }
        }
        return true;
    }
    function copyCharacterPropertiesWithoutFont(source,target) {
        var properties=["pointSize","leading","horizontalScale","verticalScale","skew","tracking","baselineShift","position","capitalization","ligatures","noBreak","fillColor","fillTint","strokeColor","strokeTint","strokeWeight","underline","strikeThru","appliedLanguage"];
        for (var i=0;i<properties.length;i++) {
            try { target[properties[i]]=source[properties[i]]; } catch(e) {}
        }
    }
    function replaceWithSeededTimes(chars,font,face) {
        var sourceCharacters=getCharacterElements(chars), seedDocument=null;
        if (!sourceCharacters.length) return false;
        try {
            seedDocument=app.documents.add(false);
            for (var i=sourceCharacters.length-1;i>=0;i--) {
                var seedFrame=seedDocument.textFrames.add();
                seedFrame.geometricBounds=[0,0,20,20];
                seedFrame.contents="M";
                var seedCharacter=seedFrame.parentStory.characters[0];
                seedCharacter.appliedFont=font;
                if (!isInstalledTimesFace(seedCharacter,face)) return false;
                var source=sourceCharacters[i], replacement=seedCharacter.move(LocationOptions.BEFORE,source);
                replacement.contents=source.contents;
                copyCharacterPropertiesWithoutFont(source,replacement);
                if (!isInstalledTimesFace(replacement,face)) { replacement.remove(); return false; }
                source.remove();
            }
            return true;
        } catch(e2) {
            return false;
        } finally {
            if (seedDocument) { try { seedDocument.close(SaveOptions.NO); } catch(e3) {} }
        }
    }
    function applyBoldItalicFont(chars) {
        var bi=findInstalledFont(CONFIG.fallbackBoldItalicFontNames);
        if (bi) {
            try { chars.appliedFont=bi; chars.fontStyle="Bold Italic"; if (isInstalledTimesFace(chars,"Bold Italic")) return true; } catch(e2) {}
            if (replaceWithSeededTimes(chars,bi,"Bold Italic")) return true;
        }
        var tnr=findInstalledFont(["Times New Roman","Times New Roman\tRegular","TimesNewRomanPSMT"]);
        if (tnr) { try { chars.appliedFont=tnr; chars.fontStyle="Bold Italic"; } catch(e) {} }
        return isInstalledTimesFace(chars,"Bold Italic");
    }
    // 表名后的空行：左对齐、首行与左缩进清零（applyParagraphStyle 已清覆盖，这里再显式压平）。
    function applyTableGap(para) {
        try { para.justification = Justification.LEFT_ALIGN; } catch(e) {}
        try { para.firstLineIndent = 0; } catch(e2) {}
        try { para.leftIndent = 0; } catch(e3) {}
    }
    // 作者简介：给开头的"作者简介：" 标签套字符样式（参考冷欣.indd 的「作者简介黑体」）。
    function applyAuthorBioLabel(doc, story, base, text) {
        var idx=text.indexOf("：");if(idx<0)idx=text.indexOf(":");if(idx<0)throw Error("作者简介标签缺少冒号");
        var f=findInstalledFont(["现 黑体"]);if(!f)throw Error("缺少作者简介标签字体：现 黑体");
        var label=story.characters.itemByRange(base,base+idx);label.appliedFont=f;label.pointSize=12;label.leading=16;
    }
    function applyEnglishLabel(para) {
        if(String(para.contents).indexOf("Absrtact:")===0)para.characters.itemByRange(0,7).contents="Abstract";
        var end=String(para.contents).indexOf(":");if(end<0)throw Error("英文摘要标签缺少冒号");
        var f=findInstalledFont(["思源黑体 CN\tBold"]);if(!f)throw Error("缺少英文摘要标签字体");
        var label=para.characters.itemByRange(0,end);label.appliedFont=f;label.pointSize=9;label.leading=13;
    }
    function findFont(names) { for (var i=0;i<names.length;i++) { try { var f=app.fonts.itemByName(names[i]); if (f.isValid && f.status===FontStatus.INSTALLED) return f; } catch(e) {} } return null; }
    function applyKerning(para, report) { for (var i=0;i<CONFIG.kerningMethods.length;i++) { try { para.characters.everyItem().kerningMethod = CONFIG.kerningMethods[i]; report.kerningApplied = true; return true; } catch(e) {} } return false; }
    function isMathChar(code) {
        if (code>=0x2200 && code<=0x22FF) return true; // 数学运算符 ∈ ∙ ⋯ ∑ ∏ √ ∞ ≈ ≠ ≤ ≥ ⊂ ⊆ ∀ ∃ …
        if (code>=0x2190 && code<=0x21FF) return true; // 箭头 → ← ↔
        if (code>=0x2A00 && code<=0x2AFF) return true; // 补充数学运算符
        if (code>=0x27C0 && code<=0x27EF) return true; // 杂项数学符号 A
        if (code>=0x2980 && code<=0x29FF) return true; // 杂项数学符号 B
        if (code===0x00D7||code===0x00F7||code===0x00B1) return true; // × ÷ ±
        if (code===0x2032||code===0x2033) return true; // ′ ″
        return false;
    }
    function normalizeUnicodeSuperSubscript(c, code) {
        var value="", position=Position.SUPERSCRIPT, i;
        if (code===0x00B9) value="1";
        else if (code===0x00B2) value="2";
        else if (code===0x00B3) value="3";
        else if (code===0x2070) value="0";
        else if (code===0x2071) value="i";
        else if (code>=0x2074 && code<=0x2079) value=String(code-0x2070);
        else if (code>=0x207A && code<=0x207E) value="+-=()".charAt(code-0x207A);
        else if (code===0x207F) value="n";
        else if (code>=0x2080 && code<=0x2089) { value=String(code-0x2080); position=Position.SUBSCRIPT; }
        else if (code>=0x208A && code<=0x208E) { value="+-=()".charAt(code-0x208A); position=Position.SUBSCRIPT; }
        else {
            var subscriptLetterCodes=[0x2090,0x2091,0x2092,0x2093,0x2095,0x2096,0x2097,0x2098,0x2099,0x209A,0x209B,0x209C];
            for (i=0;i<subscriptLetterCodes.length;i++) if (code===subscriptLetterCodes[i]) { value="aeoxhklmnpst".charAt(i); position=Position.SUBSCRIPT; break; }
        }
        if (!value) return false;
        c.contents=value;
        c.position=position;
        return true;
    }
    function findHeitiFont(doc) {
        // 1. 精确匹配尝试
        var exactList = CONFIG.heitiFontNames;
        for (var i=0; i<exactList.length; i++) {
            try { var f=app.fonts.itemByName(exactList[i]); if (f.isValid && f.status===FontStatus.INSTALLED) return f; } catch(e) {}
        }
        // 2. 模糊匹配：找名称含"黑体"或"hei"但不含"现"的字体（排除 现黑体 等错误变体）
        for (var j=0; j<app.fonts.length; j++) {
            try {
                var fn=app.fonts.item(j);
                var nm=fn.name;
                if (nm && (nm.indexOf("黑体")!==-1 || nm.toLowerCase().indexOf("hei")!==-1 || nm.toLowerCase().indexOf("heiti")!==-1)) {
                    if (nm.indexOf("现")===-1) return fn;
                }
            } catch(e2) {}
        }
        // 3. 最后回退：任何含"黑体"或"hei"的字体（仍排除"现"）
        for (var k=0; k<app.fonts.length; k++) {
            try {
                var fn2=app.fonts.item(k);
                var nm2=fn2.name;
                if (nm2 && (nm2.indexOf("黑体")!==-1 || nm2.toLowerCase().indexOf("hei")!==-1)) {
                    if (nm2.indexOf("现")===-1) return fn2;
                }
            } catch(e3) {}
        }
        return null;
    }
    function fixSpecialGlyphs(doc, para, report) {
        var mathFont=findFont(CONFIG.mathFontNames), eqFont=findFont(CONFIG.equalsFontNames), heitiFont=findHeitiFont(doc);
        var inserted=0;
        var n=para.characters.length;
        for (var i=n-1; i>=0; i--) {   // 倒序遍历：等号插入空格时不会打乱尚未处理的低位索引
            var c, s; try { c=para.characters[i]; s=c.contents; } catch(e) { continue; }
            if (!s || typeof s!=="string" || s.length!==1) continue; var code=s.charCodeAt(0);
            if (code===0xFF0B) { try { c.contents="+"; } catch(e0){} continue; } // 全角＋ → 半角+（不改字体；提取器一般已转，这里兜底）
            if (code===0xFF61) { try { c.contents="。"; report.glyphNormalized++; } catch(e00) {} continue; }
            try { if (normalizeUnicodeSuperSubscript(c,code)) { report.glyphNormalized++; continue; } } catch(e01) {}
            if (code===0x2264 || code===0x2265 || code===0xFF1C || code===0xFF1E || code===0x003C || code===0x003E || code===0xFF0D || code===0x2212) { // ≤ ≥ ＜ ＞ < > 及减号 －(全角U+FF0D) −(U+2212) → 黑体（现宋体无 U+FF0D 字形会缺字）
                if (heitiFont) { try { c.appliedFont=heitiFont; report.heitiFixed++; } catch(e1) {} }
            } else if (code===0xFF1D || code===0x003D) { // 全角＝ 或 半角= → Symbol（+下标空格）
                if (CONFIG.normalizeFullwidthEquals && code===0xFF1D) { try { c.contents="="; } catch(e2) {} }
                if (eqFont) { try { c.appliedFont=eqFont; } catch(e3) {} }
                report.equalsFixed++;
                if (CONFIG.equalsSpaceSubscript) { try { inserted += addSubscriptSpacesAround(para, i); } catch(e4) {} }
            } else if (isMathChar(code)) { // 其它数学符号 → Cambria Math
                if (mathFont) { try { c.appliedFont=mathFont; report.mathFixed++; } catch(e5) {} }
            }
        }
        return inserted;
    }
    // 在段落 para 第 idx 个字符（等号）前后各插一个下标空格，返回插入字符数
    function addSubscriptSpacesAround(para, idx) {
        var story=para.parentStory, base=para.characters[idx].index;                  // 等号在 story 中的绝对索引
        story.insertionPoints[base+1].contents=" ";                                   // 等号后插空格
        try { story.characters[base+1].position=Position.SUBSCRIPT; } catch(e1) {}
        story.insertionPoints[base].contents=" ";                                     // 等号前插空格（等号顺移到 base+1）
        try { story.characters[base].position=Position.SUBSCRIPT; } catch(e2) {}
        return 2;
    }
    function keys(obj) { var a=[]; for (var k in obj) if (obj.hasOwnProperty(k)) a.push(k); return a; }
    function buildReport(doc, report,summary) { var lines=[]; lines.push("导入完成："+report.inserted+" 段/行"); if (summary) { var roleLines=[]; for (var k in summary) if (summary.hasOwnProperty(k)) roleLines.push(k+": "+summary[k]); lines.push("\n结构统计：\n"+roleLines.join("\n")); } var missP=keys(report.missingPStyles); if (missP.length) lines.push("\n未匹配到段落样式的角色："+missP.join(", ")); if (report.italicFontFailed) lines.push("\n有 "+report.italicFontFailed+" 处斜体未能自动套字体/字符样式，请检查是否需要建立'斜体'字符样式。");
        if (report.boldItalicFontFailed) lines.push("\n有 "+report.boldItalicFontFailed+" 处 Bold Italic 未能套 Times New Roman Bold Italic，请检查该字体是否已激活。");
        lines.push("\n字偶间距：" + (report.kerningApplied ? "已设为 原始设定-仅罗马字" : "⚠ 未能设置（请检查 InDesign 版本的字偶间距值）"));
        lines.push("数学符号套 Cambria Math："+report.mathFixed+" 处" + (findFont(CONFIG.mathFontNames)?"":"  ⚠ 未找到 Cambria Math 字体"));
        lines.push("≤ ≥ ＜ ＞ 套黑体："+report.heitiFixed+" 处" + (findHeitiFont(doc)?"":"  ⚠ 未找到任何黑体/Heiti 字体（已排除现黑体）"));
        lines.push("等号套 Symbol："+report.equalsFixed+" 处"+(CONFIG.equalsSpaceSubscript?"（前后加下标空格）":"") + (findFont(CONFIG.equalsFontNames)?"":"  ⚠ 未找到 Symbol 字体"));
        lines.push("缺字字符归一化："+report.glyphNormalized+" 处（｡、可无歧义还原的 Unicode 上下标字符）");
        return lines.join("\n"); }
})();
