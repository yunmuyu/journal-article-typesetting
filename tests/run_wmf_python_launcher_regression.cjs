const assert = require('node:assert/strict');
const { test } = require('node:test');
const { run } = require('./run_wmf_text_positions_regression.cjs');
const ok = { status: 0, stdout: '1\n', stderr: '' };
const passed = { status: 0, stdout: 'PASS WMF\n', stderr: '' };

function scenario(results, env = {}, platform = 'win32') {
  const calls = [];
  return {
    calls,
    execute() {
      return run({ env, platform, spawnSync(command, args) {
        calls.push([command, args]);
        assert.ok(results.length, 'unexpected interpreter retry');
        return results.shift();
      } });
    }
  };
}

test('Windows launcher runs the actual WMF script with Python 3', () => {
  const s = scenario([ok, passed]);
  assert.equal(s.execute(), 'PASS WMF');
  assert.deepEqual(s.calls.map(call => call[0]), ['py', 'py']);
  assert.deepEqual(s.calls[1][1].slice(0, 1), ['-3']);
  assert.ok(s.calls[1][1][1].endsWith('test_wmf_text_positions.py'));
});

test('missing commands and Store aliases fall back to an installed interpreter', () => {
  const s = scenario([{ status: null, error: Error('spawn py ENOENT') },
    { status: 9009, stdout: '', stderr: 'Python was not found' }, ok, passed]);
  assert.equal(s.execute(), 'PASS WMF');
  assert.deepEqual(s.calls.map(call => call[0]), ['py', 'python3', 'python', 'python']);
});

test('explicit interpreter paths with spaces are passed as one command', () => {
  const s = scenario([ok, passed], { JOURNAL_PYTHON: 'D:\\Python tools\\python.exe' });
  assert.equal(s.execute(), 'PASS WMF');
  assert.equal(s.calls[0][0], 'D:\\Python tools\\python.exe');
  assert.equal(s.calls[1][1].length, 1);
});

test('an invalid explicit override reports the launch error without fallback', () => {
  const s = scenario([{ status: null, error: Error('spawn missing ENOENT') }],
    { JOURNAL_PYTHON: 'missing' });
  assert.throws(() => s.execute(), /PYTHON3_REQUIRED[\s\S]*spawn missing ENOENT/);
  assert.equal(s.calls.length, 1);
});

test('all unavailable interpreters report actionable diagnostics', () => {
  const s = scenario([{ status: null, error: Error('ENOENT') },
    { status: 9009, stdout: '', stderr: 'Store alias' },
    { status: 0, stdout: '0\n', stderr: '' }]);
  assert.throws(() => s.execute(), /PYTHON3_REQUIRED[\s\S]*JOURNAL_PYTHON[\s\S]*ENOENT[\s\S]*Store alias/);
});

test('a real WMF assertion failure is never retried with another interpreter', () => {
  const s = scenario([ok, { status: 1, stdout: '', stderr: 'AssertionError: positions' }]);
  assert.throws(() => s.execute(), /AssertionError: positions/);
  assert.equal(s.calls.length, 2);
});

test('signal termination of the real test is reported', () => {
  const s = scenario([ok, { status: null, stdout: '', stderr: '', signal: 'SIGTERM' }]);
  assert.throws(() => s.execute(), /signal SIGTERM/);
  assert.equal(s.calls.length, 2);
});

test('Unix resolves python3 without invoking the Windows launcher', () => {
  const s = scenario([ok, passed], {}, 'linux');
  assert.equal(s.execute(), 'PASS WMF');
  assert.equal(s.calls[0][0], 'python3');
});
