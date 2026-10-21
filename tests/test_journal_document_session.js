const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const project = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(project, '2-导入_InDesign', 'journal_document_session.jsxinc'), 'utf8');

function FakeFile(value) {
    const fsName = path.win32.resolve(String(value).replaceAll('/', '\\'));
    return {fsName, name: encodeURI(path.win32.basename(fsName))};
}

const sandbox = {File: FakeFile, Error, UserInteractionLevels: {NEVER_INTERACT: 0}};
vm.createContext(sandbox);
vm.runInContext(source, sandbox, {filename: 'journal_document_session.jsxinc'});
const Session = sandbox.JournalDocumentSession;
if (!Session) throw new Error('JournalDocumentSession was not exported');

function makeDocument(filePath, id) {
    return {
        id,
        isValid: true,
        fullName: FakeFile(filePath),
        saveCalls: 0,
        closeCalls: [],
        save() { this.saveCalls += 1; },
        close(option) { this.closeCalls.push(option); this.isValid = false; }
    };
}

function makeApp(documents, openBehavior) {
    return {
        documents,
        scriptPreferences: {userInteractionLevel: 7},
        activeDocument: documents[0] || null,
        openCalls: 0,
        open(file) {
            this.openCalls += 1;
            if (openBehavior) return openBehavior(file);
            const document = makeDocument(file.fsName, 100 + this.openCalls);
            this.documents.push(document);
            return document;
        }
    };
}

function expectCode(code, action) {
    let error = null;
    try { action(); } catch (caught) { error = caught; }
    if (!error || !String(error.message || error).includes(code)) {
        throw new Error(`expected ${code}, got ${error && (error.message || error)}`);
    }
}

// Given an owned QA document and a different active document.
{
    const other = makeDocument('C:/work/other-QA.indd', 1);
    const app = makeApp([other]);
    const session = Session.acquire(app, 'C:/work/article-QA.indd');
    app.activeDocument = other;
    // When the owned session is saved and closed, then only its exact document is touched.
    Session.save(session.document, session);
    const closed = Session.close(session.document, session, 'NO_SAVE');
    if (!session.openedHere || !closed) throw new Error('owned session was not closed');
    if (session.document.saveCalls !== 1 || session.document.closeCalls.length !== 1) throw new Error('owned target was not saved and closed once');
    if (other.saveCalls !== 0 || other.closeCalls.length !== 0) throw new Error('active non-target document was touched');
}

// Given the exact target was already open, closing its session must be a no-op or an explicit refusal.
{
    const target = makeDocument('C:/work/article-copy.indd', 20);
    const app = makeApp([target]);
    const session = Session.acquire(app, 'c:/work/nested/../ARTICLE-COPY.indd');
    if (session.openedHere || app.openCalls !== 0) throw new Error('preopened document was opened again');
    if (Session.close(target, session, 'NO_SAVE') !== false || target.closeCalls.length !== 0) throw new Error('preopened document was closed');
    expectCode('SESSION_PREOPENED_CLOSE_FORBIDDEN', () => Session.close(target, session, 'NO_SAVE', true));
    if (target.closeCalls.length !== 0) throw new Error('rejected preopened close touched document');
}

// Given a session, changing either target path or document id must reject assert/save/close.
{
    const target = makeDocument('C:/work/identity-QA.indd', 30);
    const session = Session.acquire(makeApp([target]), 'C:/work/identity-QA.indd');
    target.fullName = FakeFile('C:/work/replaced-QA.indd');
    expectCode('TARGET_PATH_CHANGED', () => Session.assertIdentity(target, session));
    expectCode('TARGET_PATH_CHANGED', () => Session.save(target, session));
    expectCode('TARGET_PATH_CHANGED', () => Session.close(target, session, 'NO_SAVE'));
    if (target.saveCalls || target.closeCalls.length) throw new Error('path mismatch still mutated document');
}
{
    const target = makeDocument('C:/work/identity2-QA.indd', 31);
    const session = Session.acquire(makeApp([target]), 'C:/work/identity2-QA.indd');
    target.id = 32;
    expectCode('TARGET_ID_CHANGED', () => Session.assertIdentity(target, session));
    expectCode('TARGET_ID_CHANGED', () => Session.save(target, session));
    expectCode('TARGET_ID_CHANGED', () => Session.close(target, session, 'NO_SAVE'));
}

// Given open fails, no existing document may be closed as cleanup.
{
    const existing = makeDocument('C:/work/existing-QA.indd', 40);
    const app = makeApp([existing], () => { throw new Error('OPEN_FAILED'); });
    expectCode('OPEN_FAILED', () => Session.acquire(app, 'C:/work/new-QA.indd'));
    if (existing.closeCalls.length !== 0) throw new Error('open failure closed an existing document');
}

// Given an unrelated unsaved Untitled document, it has no absolute target identity and is skipped.
{
    const untitled = {id: 41, saved: false, isValid: true, closeCalls: []};
    Object.defineProperty(untitled, 'fullName', {get() { throw new Error('UNSAVED_HAS_NO_FULLNAME'); }});
    untitled.close = option => untitled.closeCalls.push(option);
    const app = makeApp([untitled]);
    const session = Session.acquire(app, 'C:/work/alongside-QA.indd');
    if (!session.openedHere || app.openCalls !== 1) throw new Error('unsaved unrelated document blocked target open');
    if (untitled.closeCalls.length !== 0 || !untitled.isValid) throw new Error('unsaved unrelated document was changed');
}

// Given a saved document whose full path cannot be read, acquisition fails closed.
{
    const unreadable = {id: 42, saved: true, isValid: true, closeCalls: []};
    Object.defineProperty(unreadable, 'fullName', {get() { throw new Error('FULLNAME_BROKEN'); }});
    unreadable.close = option => unreadable.closeCalls.push(option);
    const app = makeApp([unreadable]);
    expectCode('TARGET_DOCUMENT_PATH_UNAVAILABLE', () => Session.acquire(app, 'C:/work/fail-closed-QA.indd'));
    if (app.openCalls !== 0 || unreadable.closeCalls.length !== 0) throw new Error('unreadable saved document changed application state');
}

// Given two open documents resolve to the same canonical path, acquisition is ambiguous and must stop.
{
    const first = makeDocument('C:/work/duplicate-QA.indd', 50);
    const second = makeDocument('c:/work/DUPLICATE-QA.indd', 51);
    const app = makeApp([first, second]);
    expectCode('TARGET_DOCUMENT_COUNT 2', () => Session.acquire(app, 'C:/work/duplicate-QA.indd'));
    if (app.openCalls !== 0 || first.closeCalls.length || second.closeCalls.length) throw new Error('duplicate match changed application state');
}

// Production-looking paths are refused before the application is inspected or opened.
{
    const app = makeApp([]);
    expectCode('PRODUCTION_PATH_FORBIDDEN', () => Session.acquire(app, 'C:/work/article.indd'));
    if (app.openCalls !== 0) throw new Error('production target was opened');
}

// A Chinese QA-copy name remains safe when File.name is URI-encoded by ExtendScript.
{
    const app = makeApp([]);
    const session = Session.acquire(app, 'C:/work/文章副本.indd');
    if (!session.openedHere || app.openCalls !== 1) throw new Error('URI-encoded Chinese copy name was rejected');
}

// An indexed InDesign specifier must be resolved before opening another document reorders the collection.
{
    const target = makeDocument('C:/work/article-QA.indd', 80);
    const library = makeDocument('C:/work/library-QA.indd', 81);
    let current = target;
    const indexed = {get id(){return current.id;},get fullName(){return current.fullName;},get isValid(){return true;},getElements(){return [current];}};
    const session = Session.acquire(makeApp([indexed]), 'C:/work/article-QA.indd');
    current = library;
    Session.save(session.document, session);
    if(target.saveCalls!==1||library.saveCalls!==0)throw new Error('indexed specifier retargeted the template');
}
console.log('PASS document session owns exact path/id and never retargets active or preopened documents');
