const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '../2-导入_InDesign');
const context = {File: value => ({fsName: String(value).toLowerCase()}), UserInteractionLevels: {NEVER_INTERACT: 0}};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(root, 'journal_document_session.jsxinc'), 'utf8'), context);
const session = context.JournalDocumentSession;
function makeApp(fail = false) {
    const app = {documents: [], scriptPreferences: {userInteractionLevel: 7}, open() {
        assert.equal(this.scriptPreferences.userInteractionLevel, 0, 'opening must suppress informational dialogs before app.open');
        if (fail) throw Error('OPEN_FAILED');
        const d = {id: 1, isValid: true, fullName: {fsName: 'f:/work/a_qa.indd'}, closeCalls: 0, close() {this.closeCalls++;}};
        this.documents.push(d); return d;
    }};
    return app;
}
{
    const app = makeApp(); const s = session.acquire(app, 'f:/work/a_qa.indd');
    assert.equal(app.scriptPreferences.userInteractionLevel, 7);
    assert.equal(s.openedHere, true);
}
{
    const app = makeApp(true); assert.throws(() => session.acquire(app, 'f:/work/a_qa.indd'), /OPEN_FAILED/);
    assert.equal(app.scriptPreferences.userInteractionLevel, 7, 'failed opens must restore interaction');
}
{
    const app = makeApp();
    assert.throws(() => session.withReadOnlyDocument(app, 'f:/work/a_qa.indd', () => {throw Error('CAPTURE_FAILED');}, 'NO'), /CAPTURE_FAILED/);
    assert.equal(app.documents[0].closeCalls, 1, 'owned read-only document must close on failure');
}
{
    const app = makeApp(); session.acquire(app, 'f:/work/a_qa.indd');
    session.withReadOnlyDocument(app, 'f:/work/a_qa.indd', () => 42, 'NO');
    assert.equal(app.documents[0].closeCalls, 0, 'preopened user document must stay open');
}
console.log('PASS suppress dialogs before opening, restore interaction, close owned read sessions only');
const entry = fs.readFileSync(path.join(root, 'Use-JournalDocumentSession.ps1'), 'utf8');
assert.ok(entry.includes('DOCUMENT_SESSION_APPLICATION_CHANGED'), 'restarted processes must invalidate old document sessions');
assert.ok(entry.indexOf('DOCUMENT_SESSION_APPLICATION_CHANGED') < entry.indexOf('Invoke-JournalInDesignScript -Application'), 'process check must happen before native operations');
const snapshot = fs.readFileSync(path.join(root, 'Export-JournalRegressionSnapshot.ps1'), 'utf8');
assert.ok(snapshot.includes('withReadOnlyDocument(app,entry.documentPath'), 'real snapshot entry must release owned reads');
