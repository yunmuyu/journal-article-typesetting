var JournalQaTemplate = (function () {
    var REQUIRED_SLOTS = ["front-title", "front-abstract", "body-left", "body-right", "received-fund", "doi"];
    function fail(code, detail) { throw Error(code + (detail ? " " + detail : "")); }
    function pathOf(document) {
        try { return File(document.fullName).fsName.toLowerCase(); } catch (_) { return ""; }
    }
    function identityOf(document, file) {
        var expected = file.fsName.toLowerCase(), actual = pathOf(document);
        if (actual !== expected) fail("TARGET_PATH_CHANGED", "expected=" + expected + " actual=" + actual);
        return { path: expected, id: document.id };
    }
    function closeExact(document, identity, saveOption) {
        if (!document || !document.isValid) fail("TARGET_DOCUMENT_INVALID");
        var actual = pathOf(document);
        if (actual !== identity.path) fail("TARGET_PATH_CHANGED", "expected=" + identity.path + " actual=" + actual);
        if (document.id !== identity.id) fail("TARGET_ID_CHANGED", "expected=" + identity.id + " actual=" + document.id);
        document.close(saveOption);
    }
    function sourceDocument(file) {
        var wanted = file.fsName.toLowerCase();
        for (var i = 0; i < app.documents.length; i++) {
            if (pathOf(app.documents[i]) === wanted) return { document: app.documents[i], openedHere: false };
        }
        return { document: app.open(file, false), openedHere: true };
    }
    function readEntryProperty(entry, property) {
        try {
            var value;
            if (property === "name") value = entry.name;
            else if (property === "appliedFont") {
                value = entry.appliedFont;
                try { value = value.name; } catch (_) {}
            } else if (property === "fontStyle") value = entry.fontStyle;
            else if (property === "relativeSize") value = entry.relativeSize;
            else if (property === "horizontalScale") value = entry.horizontalScale;
            else if (property === "verticalScale") value = entry.verticalScale;
            else if (property === "baselineShift") value = entry.baselineShift;
            else return { available: false };
            if (typeof value === "number") value = Number(value).toFixed(6);
            return { available: true, value: String(value) };
        } catch (_) { return { available: false }; }
    }
    function compareCompositeFont(sourceFont, targetFont) {
        var sourceEntries = sourceFont.compositeFontEntries, targetEntries = targetFont.compositeFontEntries;
        if (sourceEntries.length !== targetEntries.length) fail("COMPOSITE_FONT_MISMATCH", sourceFont.name + " entry-count");
        var properties = ["name", "appliedFont", "fontStyle", "relativeSize", "horizontalScale", "verticalScale", "baselineShift"], compared = 0;
        for (var i = 0; i < sourceEntries.length; i++) for (var j = 0; j < properties.length; j++) {
            var property = properties[j], sourceValue = readEntryProperty(sourceEntries[i], property), targetValue = readEntryProperty(targetEntries[i], property);
            if (!sourceValue.available || !targetValue.available) continue;
            compared++;
            if (sourceValue.value !== targetValue.value) fail("COMPOSITE_FONT_MISMATCH", sourceFont.name + " entry-" + i + " " + property);
        }
        if (!compared) fail("COMPOSITE_FONT_UNVERIFIABLE", sourceFont.name);
    }
    function isCompositeFontSentinel(font) {
        var name;
        try { name = String(font.name); } catch (_) { return false; }
        name = name.replace(/^[\[\u3010\uFF3B]\s*/, "").replace(/\s*[\]\u3011\uFF3D]$/, "").replace(/\s+/g, " ").toLowerCase();
        return name === "no composite font" || name === "无复合字体" || name === "無複合字體" || name === "合成フォントなし" || name === "複合フォントなし" || name === "コンポジットフォントなし" || name === "복합 글꼴 없음";
    }
    function verifyCompositeFonts(source, target) {
        var names = [];
        for (var i = 0; i < source.compositeFonts.length; i++) {
            var sourceFont = source.compositeFonts[i];
            if (isCompositeFontSentinel(sourceFont)) continue;
            var targetFont = target.compositeFonts.itemByName(sourceFont.name);
            if (!targetFont.isValid) fail("COMPOSITE_FONT_MISSING", sourceFont.name);
            compareCompositeFont(sourceFont, targetFont);
            names.push(sourceFont.name);
        }
        return names;
    }
    function keepItem(item, roles) {
        if (/^(spacing-guide|article-footer-separator)/.test(String(item.label))) return true;
        if (item.constructor.name !== "TextFrame") return false;
        var role = item.parentStory.extractLabel("journal-role");
        for (var i = 0; i < roles.length; i++) if (role === roles[i]) return true;
        return false;
    }
    function clearArticleObjects(document, roles) {
        var retained = 0, removed = 0, cleared = {}, items = [];
        for (var pageIndex = 0; pageIndex < document.pages.length; pageIndex++) {
            var pageItems = document.pages[pageIndex].pageItems.everyItem().getElements();
            for (var pageItemIndex = 0; pageItemIndex < pageItems.length; pageItemIndex++) items.push(pageItems[pageItemIndex]);
        }
        for (var i = items.length - 1; i >= 0; i--) {
            var item = items[i];
            if (keepItem(item, roles)) {
                retained++;
                if (item.constructor.name === "TextFrame") {
                    var story = item.parentStory, role = story.extractLabel("journal-role");
                    if (!cleared[story.id]) {
                        story.contents = "";
                        story.insertLabel("journal-role", role);
                        cleared[story.id] = true;
                    }
                }
            } else try { item.remove(); removed++; } catch (_) {}
        }
        return { retained: retained, removed: removed };
    }
    function removeUnscopedPasteboardStories(document) {
        var removed = 0;
        for (var storyIndex = document.stories.length - 1; storyIndex >= 0; storyIndex--) {
            var story = document.stories[storyIndex];
            if (story.extractLabel("journal-role")) continue;
            var pageBound = false;
            for (var frameIndex = 0; frameIndex < story.textContainers.length; frameIndex++) {
                var page = story.textContainers[frameIndex].parentPage;
                // Master pages have a negative documentOffset but still own page content.
                if (page) { pageBound = true; break; }
            }
            if (pageBound) continue;
            for (frameIndex = story.textContainers.length - 1; frameIndex >= 0; frameIndex--) {
                if (story.textContainers[frameIndex].isValid) story.textContainers[frameIndex].remove();
            }
            removed++;
        }
        return removed;
    }
    function normalizeLegacyBodyStyles(document) {
        var styles = document.allParagraphStyles;
        for (var styleIndex = 0; styleIndex < styles.length; styleIndex++) {
            if (styles[styleIndex].name !== "正文_wrd_1" && styles[styleIndex].name !== "正文") continue;
            styles[styleIndex].pointSize = 10.5;
            styles[styleIndex].leading = 15;
        }
    }
    function normalizeBodyPages(document) {
        var ordered = [], removalIds = [], i, j;
        for (i = 0; i < document.pages.length; i++) {
            var candidates = [], items = document.pages[i].textFrames;
            for (j = 0; j < items.length; j++) if (items[j].parentStory.extractLabel("journal-role") === "body") candidates.push(items[j]);
            if (candidates.length < 2) fail("BODY_TEMPLATE_PAGE", i);
            candidates.sort(function (a, b) { var ay = a.geometricBounds[0], by = b.geometricBounds[0]; if (Math.abs(ay - by) > .01) return ay - by; return a.geometricBounds[1] - b.geometricBounds[1]; });
            var kept = [candidates[0], candidates[1]];
            kept.sort(function (a, b) { return a.geometricBounds[1] - b.geometricBounds[1]; });
            var left = kept[0], right = kept[1];
            if (left.id === right.id) fail("BODY_TEMPLATE_COLUMNS", i);
            for (j = 0; j < candidates.length; j++) if (candidates[j].id !== left.id && candidates[j].id !== right.id) removalIds.push(candidates[j].id);
            if (i > 0) {
                if (document.pages[i].side === PageSideOptions.LEFT_HAND) { left.geometricBounds = [26, 14.5, 265, 100]; right.geometricBounds = [26, 107, 265, 192.5]; }
                else { left.geometricBounds = [26, 17.5, 265, 103]; right.geometricBounds = [26, 110, 265, 195.5]; }
            }
            ordered.push(left); ordered.push(right);
        }
        for (i = removalIds.length - 1; i >= 0; i--) {
            var removal = document.pageItems.itemByID(removalIds[i]);
            if (removal.isValid) removal.remove();
        }
        ordered = [];
        for (i = 0; i < document.pages.length; i++) {
            var remaining = [], pageFrames = document.pages[i].textFrames;
            for (j = 0; j < pageFrames.length; j++) if (pageFrames[j].parentStory.extractLabel("journal-role") === "body") remaining.push(pageFrames[j]);
            if (remaining.length !== 2) fail("BODY_TEMPLATE_NORMALIZE", i + " " + remaining.length);
            remaining.sort(function (a, b) { return a.geometricBounds[1] - b.geometricBounds[1]; });
            if (remaining[1].geometricBounds[1] - remaining[0].geometricBounds[1] < 80) fail("BODY_TEMPLATE_COLUMN_SIDES", i);
            ordered.push(remaining[0]); ordered.push(remaining[1]);
        }
        for (i = ordered.length - 1; i >= 0; i--) if (ordered[i].isValid) ordered[i].nextTextFrame = NothingEnum.NOTHING;
        for (i = 0; i < ordered.length - 1; i++) ordered[i].nextTextFrame = ordered[i + 1];
        ordered[0].parentStory.insertLabel("journal-role", "body");
        for (i = 0; i < ordered.length; i++) { ordered[i].label = "article-body"; ordered[i].textFramePreferences.insetSpacing = [0, 0, 0, 0]; ordered[i].textFramePreferences.firstBaselineOffset = FirstBaseline.ASCENT_OFFSET; ordered[i].textFramePreferences.verticalJustification = VerticalJustification.TOP_ALIGN; }
    }
    function verifyBodyStyle(document, name) {
        if (!name) return "";
        var matches = [], styles = document.allParagraphStyles;
        for (var i = 0; i < styles.length; i++) if (styles[i].name === name) matches.push(styles[i]);
        if (matches.length !== 1) fail("BODY_STYLE_COUNT", name + " " + matches.length);
        var style = matches[0];
        if (Math.abs(Number(style.pointSize) - 10.5) > .001 || Math.abs(Number(style.leading) - 15) > .001) fail("BODY_STYLE_METRICS", name + " " + style.pointSize + "/" + style.leading);
        document.insertLabel("journal-body-style", name);
        return name;
    }
    function countStructural(document, roles) {
        var result = {}, i;
        for (i = 0; i < roles.length; i++) result[roles[i]] = 0;
        for (i = 0; i < document.stories.length; i++) {
            var role = document.stories[i].extractLabel("journal-role");
            if (typeof result[role] !== "undefined") result[role] += document.stories[i].textContainers.length;
        }
        return result;
    }
    function addAliases(frame, slot, aliases) {
        frame.insertLabel("journal-slot", slot);
        frame.insertLabel("journal-slot-aliases", aliases.join(","));
    }
    function registerSlots(document) {
        var byRole = {}, i, j;
        for (i = 0; i < document.stories.length; i++) {
            var story = document.stories[i], role = story.extractLabel("journal-role");
            if (!byRole[role]) byRole[role] = [];
            var frames = story.textContainers;
            for (j = 0; j < frames.length; j++) byRole[role].push(frames[j]);
        }
        if (!byRole.front || byRole.front.length !== 1) fail("SLOT_SOURCE_COUNT", "front " + (byRole.front ? byRole.front.length : 0));
        if (!byRole.body || byRole.body.length < 2) fail("SLOT_SOURCE_MISSING", "body columns");
        if (!byRole.footer || byRole.footer.length !== 1) fail("SLOT_SOURCE_COUNT", "footer " + (byRole.footer ? byRole.footer.length : 0));
        if (!byRole.doi || byRole.doi.length !== 1) fail("SLOT_SOURCE_COUNT", "doi " + (byRole.doi ? byRole.doi.length : 0));
        addAliases(byRole.front[0], "frontmatter", ["front-title", "front-abstract"]);
        addAliases(byRole.body[0], "body-left", ["body-left"]);
        addAliases(byRole.body[1], "body-right", ["body-right"]);
        addAliases(byRole.footer[0], "received-fund", ["received-fund"]);
        addAliases(byRole.doi[0], "doi", ["doi"]);
        return slotInventory(document);
    }
    function slotInventory(document) {
        var found = {}, items = document.allPageItems;
        for (var i = 0; i < items.length; i++) {
            var aliases = String(items[i].extractLabel("journal-slot-aliases") || "").split(",");
            for (var j = 0; j < aliases.length; j++) if (aliases[j]) {
                if (!found[aliases[j]]) found[aliases[j]] = [];
                found[aliases[j]].push(items[i]);
            }
        }
        var result = {};
        for (i = 0; i < REQUIRED_SLOTS.length; i++) {
            var name = REQUIRED_SLOTS[i], matches = found[name] || [];
            if (matches.length !== 1) fail("SLOT_COUNT", name + " " + matches.length);
            result[name] = { itemId: matches[0].id, label: String(matches[0].label), bounds: boundsOf(matches[0]) };
        }
        return result;
    }
    function boundsOf(item) {
        var source = item.geometricBounds, bounds = [];
        for (var i = 0; i < source.length; i++) bounds.push(Number(source[i]));
        return bounds;
    }
    function closeNumber(actual, expected) { return Math.abs(Number(actual) - Number(expected)) <= .01; }
    function assertBounds(code, actual, expected) {
        if (actual.length !== expected.length) fail(code, "length");
        for (var i = 0; i < expected.length; i++) if (!closeNumber(actual[i], expected[i])) fail(code, i + " " + actual[i] + " expected " + expected[i]);
    }
    function verifyFixedGeometry(document, slots, sourceBodyBounds) {
        var fixed = {
            doi:[20.4,14.5,23.8527777777798,86.2935004340043],
            frontTop:30.3541666666667, frontLeft:21.1055555555556, frontWidth:164.894444444444,
            footerBottom:265.04305556, footerLeft:14.5, footerWidth:85.5,
            firstLeft:sourceBodyBounds[0], firstRight:sourceBodyBounds[1]
        };
        var front = slots["front-title"].bounds, footer = slots["received-fund"].bounds;
        assertBounds("FIXED_DOI", slots.doi.bounds, fixed.doi);
        if (!closeNumber(front[0], fixed.frontTop) || !closeNumber(front[1], fixed.frontLeft) || !closeNumber(front[3] - front[1], fixed.frontWidth)) fail("FIXED_FRONT", json(front));
        if (!closeNumber(footer[2], fixed.footerBottom) || !closeNumber(footer[1], fixed.footerLeft) || !closeNumber(footer[3] - footer[1], fixed.footerWidth)) fail("FIXED_FOOTER", json(footer));
        assertBounds("FIXED_FIRST_BODY_LEFT", slots["body-left"].bounds, fixed.firstLeft);
        assertBounds("FIXED_FIRST_BODY_RIGHT", slots["body-right"].bounds, fixed.firstRight);
        document.insertLabel("journal-fixed-geometry", json(fixed));
        return fixed;
    }
    function structuralInventory(document, roles) {
        var result = { roles: {}, anchors: [] }, i, j;
        for (i = 0; i < roles.length; i++) result.roles[roles[i]] = [];
        for (i = 0; i < document.stories.length; i++) {
            var story = document.stories[i], role = story.extractLabel("journal-role");
            if (typeof result.roles[role] === "undefined") continue;
            for (j = 0; j < story.textContainers.length; j++) {
                var frame = story.textContainers[j];
                result.roles[role].push({ pageIndex: frame.parentPage ? frame.parentPage.documentOffset : -1, bounds: boundsOf(frame), label: String(frame.label) });
            }
        }
        for (i = 0; i < document.pages.length; i++) {
            var items = document.pages[i].pageItems.everyItem().getElements();
            for (j = 0; j < items.length; j++) if (/^(spacing-guide|article-footer-separator)/.test(String(items[j].label))) result.anchors.push({ pageIndex: i, bounds: boundsOf(items[j]), label: String(items[j].label), nonprinting: Boolean(items[j].nonprinting) });
        }
        return result;
    }
    function countTables(document) {
        var count = 0;
        for (var i = 0; i < document.stories.length; i++) count += document.stories[i].tables.length;
        return count;
    }
    function json(value) {
        if (value === null) return "null";
        if (typeof value === "number" || typeof value === "boolean") return String(value);
        if (typeof value === "string") return '"' + value.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r/g, "\\r").replace(/\n/g, "\\n") + '"';
        if (value instanceof Array) { var a = []; for (var i = 0; i < value.length; i++) a.push(json(value[i])); return "[" + a.join(",") + "]"; }
        var p = []; for (var key in value) if (value.hasOwnProperty(key)) p.push(json(key) + ":" + json(value[key])); return "{" + p.join(",") + "}";
    }
    function run(job) {
        var previous = app.scriptPreferences.userInteractionLevel;
        var source = null, target = null, sourceOpenedHere = false, sourceIdentity = null, targetIdentity = null;
        try {
            app.scriptPreferences.userInteractionLevel = UserInteractionLevels.NEVER_INTERACT;
            var sourceFile = File(job.sourcePath), outputFile = File(job.outputPath);
            if (!sourceFile.exists) fail("SOURCE_MISSING", sourceFile.fsName);
            if (outputFile.exists) fail("OUTPUT_EXISTS", outputFile.fsName);
            var acquired = sourceDocument(sourceFile); source = acquired.document; sourceOpenedHere = acquired.openedHere; sourceIdentity = identityOf(source, sourceFile);
            if (source.modified) fail("SOURCE_MODIFIED");
            if (job.startPageIndex < 0 || job.startPageIndex + job.pageCount > source.pages.length) fail("PAGE_RANGE", source.pages.length);
            source.saveACopy(outputFile);
            target = app.open(outputFile, false); targetIdentity = identityOf(target, outputFile);
            for (var pageIndex = target.pages.length - 1; pageIndex >= job.startPageIndex + job.pageCount; pageIndex--) target.pages[pageIndex].remove();
            for (pageIndex = job.startPageIndex - 1; pageIndex >= 0; pageIndex--) target.pages[pageIndex].remove();
            var compositeFonts = verifyCompositeFonts(source, target);
            if (target.pages.length !== job.pageCount) fail("PAGE_COUNT", target.pages.length);
            if (target.sections.length) {
                target.sections[0].continueNumbering = false;
                target.sections[0].pageNumberStart = 2;
                target.sections[0].pageNumberStyle = PageNumberStyle.ARABIC;
                target.sections[0].sectionPrefix = "";
                target.sections[0].includeSectionPrefix = false;
            }
            if (target.pages[0].side !== PageSideOptions.LEFT_HAND) fail("LEFT_START");
            var bodyStyleName = verifyBodyStyle(target, job.bodyStyleName || "");
            var sourceBodyFrames = [], firstPageFrames = target.pages[0].textFrames;
            for (var bfi = 0; bfi < firstPageFrames.length; bfi++) if (firstPageFrames[bfi].parentStory.extractLabel("journal-role") === "body") sourceBodyFrames.push(firstPageFrames[bfi]);
            sourceBodyFrames.sort(function(a,b){return a.geometricBounds[1]-b.geometricBounds[1];});
            if(sourceBodyFrames.length !== 2) fail("FIRST_BODY_SOURCE_COUNT",sourceBodyFrames.length);
            var sourceBodyBounds = [boundsOf(sourceBodyFrames[0]),boundsOf(sourceBodyFrames[1])];
            var cleanup = clearArticleObjects(target, job.preserveRoles);
            normalizeBodyPages(target);
            var removedPasteboardStories = removeUnscopedPasteboardStories(target);
            normalizeLegacyBodyStyles(target);
            target.recompose();
            if (target.links.length || target.allGraphics.length || countTables(target)) fail("NOT_BLANK");
            var structural = countStructural(target, job.preserveRoles);
            if (!structural.front || !structural.body || !structural.footer || !structural.doi) fail("ANCHORS_MISSING", json(structural));
            var slots = registerSlots(target);
            var fixedGeometry = verifyFixedGeometry(target, slots, sourceBodyBounds);
            target.insertLabel("journal-template-contract", "qa-template-contract-v2");
            var inventory = structuralInventory(target, job.preserveRoles);
            for (var si = 0; si < target.stories.length; si++) {
                var checkedRole = target.stories[si].extractLabel("journal-role"), checked = false;
                for (var ri = 0; ri < job.preserveRoles.length; ri++) if (checkedRole === job.preserveRoles[ri]) checked = true;
                if (checked && target.stories[si].overflows) fail("OVERSET", checkedRole + " " + target.stories[si].id);
                if (!checkedRole && target.stories[si].overflows) {
                    var leftover=target.stories[si], locations=[], masterOnly=leftover.textContainers.length>0;
                    for(var lfi=0;lfi<leftover.textContainers.length;lfi++){var lf=leftover.textContainers[lfi], lp=lf.parentPage;locations.push(lp ? String(lp.name) : "pasteboard");if(!lp||lp.documentOffset>=0)masterOnly=false;}
                    if(!masterOnly)fail("PASTEBOARD_STORY_REMAINS", leftover.id+" "+String(leftover.contents).slice(0,80)+" "+locations.join(","));
                }
            }
            for (si = 0; si < target.allParagraphStyles.length; si++) if ((target.allParagraphStyles[si].name === "正文_wrd_1" || target.allParagraphStyles[si].name === "正文") && (Number(target.allParagraphStyles[si].pointSize) !== 10.5 || Number(target.allParagraphStyles[si].leading) !== 15)) fail("LEGACY_BODY_STYLE_METRICS", target.allParagraphStyles[si].name);
            target.save(outputFile);
            var result = { status: "created", sourceWasAlreadyOpen: !sourceOpenedHere, pages: target.pages.length, firstPageName: target.pages[0].name, bodyStyleName: bodyStyleName, fixedGeometry: fixedGeometry, structuralFrames: structural, structuralInventory: inventory, slots: slots, retainedItems: cleanup.retained, removedItems: cleanup.removed, removedPasteboardStories: removedPasteboardStories, paragraphStyles: target.allParagraphStyles.length, characterStyles: target.allCharacterStyles.length, tableStyles: target.allTableStyles.length, cellStyles: target.allCellStyles.length, masterSpreads: target.masterSpreads.length, compositeFonts: compositeFonts };
            closeExact(target, targetIdentity, SaveOptions.NO); target = null;
            return json(result);
        } finally {
            if (target) try { closeExact(target, targetIdentity, SaveOptions.NO); } catch (_) {}
            if (sourceOpenedHere && source) try { closeExact(source, sourceIdentity, SaveOptions.NO); } catch (_) {}
            app.scriptPreferences.userInteractionLevel = previous;
        }
    }
    return { run: run };
}());
