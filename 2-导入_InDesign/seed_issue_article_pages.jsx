// Seed new article pages at the end of the issue QA copy by duplicating the
// reference article's page structure, clearing only its article payload, and
// labelling journal roles. Existing pages, masters, styles and other articles
// are never modified.
(function (job) {
    var fail = function (code, detail) { throw Error(code + (detail ? " " + detail : "")); };
    var out = [], oldUI = app.scriptPreferences.userInteractionLevel, oldRedraw = app.scriptPreferences.enableRedraw;
    var d = null, openedHere = false;
    function allTextFrames(page) {
        var items = page.allPageItems, frames = [];
        for (var ti = 0; ti < items.length; ti++) if (items[ti].constructor.name === "TextFrame") frames.push(items[ti]);
        return frames;
    }
    function keepReceivedGroup(item) {
        if (item.constructor.name !== "Group") return false;
        var frames = allTextFrames(item);
        for (var ti = 0; ti < frames.length; ti++) {
            var paragraphs = frames[ti].parentStory.paragraphs;
            if (paragraphs.length && String(paragraphs[0].appliedParagraphStyle.name) === "收稿日期") return true;
        }
        return false;
    }
    try {
        app.scriptPreferences.userInteractionLevel = UserInteractionLevels.NEVER_INTERACT;
        var file = File(job.path);
        for (var i = 0; i < app.documents.length; i++) {
            var p = ""; try { p = String(app.documents[i].fullName.fsName); } catch (e) {}
            if (p.toLowerCase() === String(file.fsName).toLowerCase()) { d = app.documents[i]; }
        }
        if (!d) { d = app.open(file, false); openedHere = true; }
        if (d.modified) fail("SEED_TARGET_MODIFIED");
        var beforePages = d.pages.length;
        out.push("BEFORE " + beforePages);

        var refIndexes = [];
        for (var q = 0; q < job.referencePages.length; q++) {
            var idx = Number(job.referencePages[q]);
            if (idx < 0 || idx >= beforePages) fail("SEED_REFERENCE_RANGE", idx);
            refIndexes.push(idx);
        }

        var created = [];
        for (var r = 0; r < refIndexes.length; r++) {
            var source = d.pages[refIndexes[r]];
            var copy = source.duplicate(LocationOptions.AFTER, d.pages[-1]);
            created.push(copy);
        }
        d.recompose();
        out.push("AFTER " + d.pages.length);
        if (d.pages.length !== beforePages + refIndexes.length) fail("SEED_PAGE_COUNT", d.pages.length);

        // Remove payload objects that are not text frames (figures, decorative marks).
        for (var c = 0; c < created.length; c++) {
            var items = created[c].pageItems.everyItem().getElements();
            for (var ii = items.length - 1; ii >= 0; ii--) {
                var item = items[ii];
                if (item.constructor.name === "TextFrame" || keepReceivedGroup(item)) continue;
                try { item.remove(); } catch (e) {}
            }
        }
        d.recompose();

        // Clear each distinct story once, then label it by its own content signature.
        var cleared = {}, removedStories = 0;
        for (c = 0; c < created.length; c++) {
            var frames = allTextFrames(created[c]);
            for (var fi = 0; fi < frames.length; fi++) {
                var frame = frames[fi], story = frame.parentStory;
                if (cleared[story.id]) continue;
                cleared[story.id] = true;
                for (var oi = 0; oi < story.textContainers.length; oi++) {
                    var ownerPage = story.textContainers[oi].parentPage;
                    if (!ownerPage || ownerPage.documentOffset < beforePages) fail("SEED_STORY_OUTSIDE_CREATED_PAGE", story.id);
                }
                var styleName = "";
                try { styleName = story.paragraphs.length ? String(story.paragraphs[0].appliedParagraphStyle.name) : ""; } catch (e) {}
                var text = "";
                try { text = String(story.contents); } catch (e) {}
                var role = "";
                if (styleName === "大标题") role = "front";
                else if (styleName.indexOf("中图分类号") === 0) role = "doi";
                else if (styleName === "收稿日期") role = "footer";
                else if (styleName === "页眉作者") role = "";
                else if (styleName === "内文" && text.indexOf("上接") >= 0) role = "remove";
                else if (story.textContainers.length >= 2) role = "body";
                if (role === "remove") {
                    for (var ci = story.textContainers.length - 1; ci >= 0; ci--) {
                        if (story.textContainers[ci].isValid) story.textContainers[ci].remove();
                    }
                    removedStories++;
                    continue;
                }
                story.contents = "";
                if (role) story.insertLabel("journal-role", role);
            }
        }
        d.recompose();

        // Front page of the new article: the page that carries the front slot.
        var frontPage = null, bodyStory = null, frontStory = null, footerStory = null, doiStory = null;
        for (c = 0; c < created.length; c++) {
            var fs = allTextFrames(created[c]);
            for (fi = 0; fi < fs.length; fi++) {
                var s = fs[fi].parentStory, rl = String(s.extractLabel("journal-role"));
                if (rl === "front") { frontPage = created[c]; frontStory = s; }
                else if (rl === "body" && !bodyStory) bodyStory = s;
                else if (rl === "footer") footerStory = s;
                else if (rl === "doi") doiStory = s;
            }
        }
        if (!frontPage || !frontStory) fail("SEED_FRONT_SLOT");
        if (!bodyStory) fail("SEED_BODY_SLOT");
        if (!doiStory) fail("SEED_DOI_SLOT");

        // The 收稿日期 frame lives on the applied master, so the duplicated pages have
        // no page-level footer story. Derive one inside the copied page geometry, in the
        // same position and with the same style the master uses.
        if (!footerStory) {
            var masterFrame = null, masterPage = null;
            var applied = frontPage.appliedMaster;
            if (applied) {
                for (var mp = 0; mp < applied.pages.length && !masterFrame; mp++) {
                    var mpage = applied.pages[mp];
                    for (var mi = 0; mi < mpage.textFrames.length; mi++) {
                        var mtf = mpage.textFrames[mi], mstyle = "";
                        try { mstyle = mtf.paragraphs.length ? String(mtf.paragraphs[0].appliedParagraphStyle.name) : ""; } catch (e) {}
                        if (mstyle === "收稿日期") { masterFrame = mtf; masterPage = mpage; break; }
                    }
                }
            }
            // The 收稿日期 master (E/F) is applied per page side, not to the body master,
            // so fall back to the named master spreads when the applied one lacks it.
            if (!masterFrame) {
                for (var ms = 0; ms < d.masterSpreads.length && !masterFrame; ms++) {
                    var msName = String(d.masterSpreads[ms].name);
                    if (msName.indexOf("收稿") < 0) continue;
                    for (var msp = 0; msp < d.masterSpreads[ms].pages.length && !masterFrame; msp++) {
                        var mspage = d.masterSpreads[ms].pages[msp];
                        var wantRight = frontPage.side === PageSideOptions.RIGHT_HAND;
                        if (mspage.side !== undefined && String(mspage.side) !== String(frontPage.side)) continue;
                        for (var msi = 0; msi < mspage.textFrames.length; msi++) {
                            var msf = mspage.textFrames[msi], sname = "";
                            try { sname = msf.paragraphs.length ? String(msf.paragraphs[0].appliedParagraphStyle.name) : ""; } catch (e) {}
                            if (sname === "收稿日期") { masterFrame = msf; masterPage = mspage; break; }
                        }
                    }
                }
            }
            if (!masterFrame) fail("SEED_MASTER_FOOTER_STYLE");
            var mb = masterFrame.geometricBounds;
            var pageDeltaY = Number(frontPage.bounds[0]) - Number(masterPage.bounds[0]);
            var pageDeltaX = Number(frontPage.bounds[1]) - Number(masterPage.bounds[1]);
            var newFooter = frontPage.textFrames.add({
                geometricBounds: [mb[0] + pageDeltaY, mb[1] + pageDeltaX, mb[2] + pageDeltaY, mb[3] + pageDeltaX]
            });
            newFooter.label = "article-footer";
            newFooter.parentStory.insertLabel("journal-role", "footer");
            footerStory = newFooter.parentStory;
            footerStory.contents = "";
            out.push("FOOTER_DERIVED " + footerStory.id);
        }

        // Rebuild one body story across the new pages only. Duplicating a page copies
        // its story, so later pages keep the measured frame geometry but get fresh
        // empty frames threaded into the first new page's body story.
        function bodyFrameCandidates(page) {
            var frames = allTextFrames(page), found = [];
            for (var fi = 0; fi < frames.length; fi++) {
                var frame = frames[fi];
                var bounds = frame.geometricBounds;
                if (Number(bounds[2]) - Number(bounds[0]) < job.bodyFrameMinHeightMm) continue;
                var role = String(frame.parentStory.extractLabel("journal-role"));
                if (role === "front" || role === "doi" || role === "footer") continue;
                found.push(frame);
            }
            found.sort(function (a, b) {
                var ay = a.geometricBounds[0], by = b.geometricBounds[0];
                if (Math.abs(ay - by) > 0.01) return ay - by;
                return a.geometricBounds[1] - b.geometricBounds[1];
            });
            return found;
        }
        var firstBodyFrames = bodyFrameCandidates(created[0]);
        if (!firstBodyFrames.length) fail("SEED_BODY_FRAMES_FIRST");
        var keepStory = firstBodyFrames[0].parentStory;
        keepStory.insertLabel("journal-role", "body");
        for (var fd = 1; fd < firstBodyFrames.length; fd++) {
            if (String(firstBodyFrames[fd].parentStory.id) !== String(keepStory.id)) {
                fail("SEED_BODY_FIRST_PAGE_SPLIT");
            }
        }
        var created_bounds = [];
        for (c = 1; c < created.length; c++) {
            var victims = bodyFrameCandidates(created[c]), boundsList = [];
            for (fi = 0; fi < victims.length; fi++) boundsList.push(victims[fi].geometricBounds);
            for (fi = victims.length - 1; fi >= 0; fi--) {
                var victimStory = victims[fi].parentStory;
                victims[fi].remove();
                try { if (victimStory.textContainers.length === 0) victimStory.remove(); } catch (e) {}
            }
            for (fi = 0; fi < boundsList.length; fi++) created_bounds.push({ page: created[c], bounds: boundsList[fi] });
        }
        var newFrames = [];
        for (fi = 0; fi < created_bounds.length; fi++) {
            var nf = created_bounds[fi].page.textFrames.add({ geometricBounds: created_bounds[fi].bounds });
            nf.label = "article-body";
            newFrames.push(nf);
        }
        var chain = [];
        for (c = 0; c < created.length; c++) {
            var kept = [];
            for (fi = 0; fi < created[c].textFrames.length; fi++) {
                var f2 = created[c].textFrames[fi];
                if (String(f2.parentStory.id) === String(keepStory.id)) kept.push(f2);
            }
            kept.sort(function (a, b) {
                var ay = a.geometricBounds[0], by = b.geometricBounds[0];
                if (Math.abs(ay - by) > 0.01) return ay - by;
                return a.geometricBounds[1] - b.geometricBounds[1];
            });
            for (fi = 0; fi < kept.length; fi++) chain.push(kept[fi]);
        }
        if (chain.length < 2) fail("SEED_BODY_FRAMES_AFTER_MERGE", chain.length);
        for (c = chain.length - 1; c >= 0; c--) chain[c].nextTextFrame = NothingEnum.NOTHING;
        for (c = 0; c < chain.length - 1; c++) chain[c].nextTextFrame = chain[c + 1];
        bodyStory = keepStory;

        bodyStory = chain[0].parentStory;
        bodyStory.insertLabel("journal-role", "body");

        // Slot aliases consumed by the shared assembly entry.
        function alias(frame, slot, names) {
            frame.insertLabel("journal-slot", slot);
            frame.insertLabel("journal-slot-aliases", names.join(","));
        }
        alias(frontStory.textContainers[0], "frontmatter", ["front-title", "front-abstract"]);
        alias(chain[0], "body-left", ["body-left"]);
        alias(chain[1], "body-right", ["body-right"]);
        alias(footerStory.textContainers[0], "received-fund", ["received-fund"]);
        alias(doiStory.textContainers[0], "doi", ["doi"]);

        // Spacing guides and footer separator measured from this page geometry.
        var pb = frontPage.bounds, pageLeft = frontPage.side === PageSideOptions.LEFT_HAND ? job.geometry.leftPageLeftMm : job.geometry.rightPageLeftMm;
        var guideLeft = pb[1] + pageLeft, guideRight = guideLeft + job.geometry.spreadWidthMm;
        var topGuide = frontPage.rectangles.add({ geometricBounds: [pb[0] + 30, guideLeft, pb[0] + 30.1, guideRight], strokeWeight: 0 });
        topGuide.label = "spacing-guide-top"; topGuide.nonprinting = true;
        var bottomGuide = frontPage.rectangles.add({ geometricBounds: [pb[0] + 260, guideLeft, pb[0] + 260.1, guideRight], strokeWeight: 0 });
        bottomGuide.label = "spacing-guide-footer"; bottomGuide.nonprinting = true;
        var separator = frontPage.graphicLines.add({ geometricBounds: [pb[0] + 262, guideLeft, pb[0] + 262, guideRight], strokeWeight: 0.5 });
        separator.label = "article-footer-separator"; separator.nonprinting = true;

        d.insertLabel("journal-template-contract", job.templateContractVersion);
        d.insertLabel("journal-article-page-origin", String(created[0].documentOffset));
        d.recompose();

        var inventory = [];
        for (c = 0; c < created.length; c++) {
            var pg = created[c], rec = { index: pg.documentOffset, name: String(pg.name), side: String(pg.side), master: pg.appliedMaster ? String(pg.appliedMaster.name) : "", frames: pg.textFrames.length };
            inventory.push(rec.index + "," + rec.name + "," + rec.side + "," + rec.master + "," + rec.frames);
        }
        out.push("CREATED " + inventory.join(";"));
        out.push("ROLES front=" + frontStory.id + " body=" + bodyStory.id + " footer=" + footerStory.id + " doi=" + doiStory.id);
        out.push("BODYCHAIN " + chain.length);
        d.save();
    } catch (error) {
        out.push("ERROR " + error + " LINE " + error.line);
    } finally {
        try { if (openedHere && d) d.close(SaveOptions.NO); } catch (e) {}
        app.scriptPreferences.userInteractionLevel = oldUI;
        app.scriptPreferences.enableRedraw = oldRedraw;
    }
    // DoScript does not reliably return large results from long scripts; write the
    // outcome next to the document and let the wrapper read it back.
    if (job.resultPath) {
        try {
            var rf = File(job.resultPath);
            rf.encoding = "UTF-8";
            rf.open("w");
            rf.write(out.join(String.fromCharCode(10)));
            rf.close();
        } catch (writeError) {}
    }
    // The IIFE needs an explicit return even when its caller assigns the result.
    return out.join(String.fromCharCode(10));
})(JournalSeedJob);
