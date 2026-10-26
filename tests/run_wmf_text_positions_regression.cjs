const assert = require('node:assert/strict');
const cp = require('node:child_process');
const path = require('node:path');

function run({ spawnSync = cp.spawnSync, env = process.env, platform = process.platform } = {}) {
  // An explicit interpreter is authoritative; otherwise prefer the Windows launcher
  // over the Microsoft Store python alias, then the usual Unix command names.
  const candidates = env.JOURNAL_PYTHON ? [[env.JOURNAL_PYTHON, []]] :
    (platform === 'win32' ? [['py', ['-3']]] : []).concat([['python3', []], ['python', []]]);
  const failures = [];
  for (const [command, prefix] of candidates) {
    const probe = spawnSync(command, [...prefix, '-c',
      'import sys; print(int(sys.version_info >= (3, 8)))'], { encoding: 'utf8' });
    if (probe.error || probe.status !== 0 || probe.stdout.trim() !== '1') {
      failures.push(`${command}: ${probe.error ? probe.error.message :
        `status ${probe.status}, signal ${probe.signal || 'none'}; ${probe.stderr || probe.stdout}`}`);
      continue;
    }
    const result = spawnSync(command, [...prefix, path.join(__dirname, 'test_wmf_text_positions.py')],
      { encoding: 'utf8' });
    assert.equal(result.status, 0, `WMF regression failed with ${command}:\n` +
      (result.error ? result.error.message : '') + (result.stdout || '') + (result.stderr || '') +
      (result.signal ? `\nsignal ${result.signal}` : ''));
    return result.stdout.trim();
  }
  throw Error('PYTHON3_REQUIRED: set JOURNAL_PYTHON to an installed Python 3.8+ executable.\n' +
    failures.join('\n'));
}

if (require.main === module) console.log(run());
module.exports = { run };
