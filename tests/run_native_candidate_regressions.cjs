const { spawnSync } = require('node:child_process');
const path = require('node:path');

const nodeTests = [
    'bottom_interval_behavior_regression.js',
    'prepreview_gate_behavior_regression.js',
    'run_article_scope_regression.cjs',
    'run_article_scope_import_regression.cjs',
    'run_assembly_flow_regression.cjs',
    'run_existing_front_refit_regression.cjs',
    'run_flow_panel_policy_regression.cjs',
    'run_formula_alignment_regression.cjs',
    'run_frame_body_leading_regression.cjs',
    'run_funding_number_break_regression.cjs',
    'run_gap_solver_regression.cjs',
    'run_heading_following_lines_regression.cjs',
    'run_line_metric_diagnostic_regression.cjs',
    'run_native_table_gap_regression.cjs',
    'run_natural_tail_balance_regression.cjs',
    'run_page_furniture_regression.cjs',
    'run_panel_center_regression.cjs',
    'run_review_contract_regression.cjs',
    'run_scoped_assembly_plan_regression.cjs',
    'run_single_character_title_regression.cjs',
    'run_single_line_page_continuation_regression.cjs',
    'run_source_italic_idempotence_regression.cjs',
    'run_split_table_trial_regression.cjs',
    'run_table_continuation_regression.cjs',
    'run_table_continuation_sync_regression.cjs',
    'run_table_minimum_width_regression.cjs',
    'run_table_native_format_regression.cjs',
    'run_table_special_character_audit_regression.cjs',
];

const powershellTests = [
    'run_batch_parallel_lanes_regression.ps1',
    'run_bottom_solver_regression.ps1',
    'run_offline_candidate_regressions.ps1',
];

const root = path.resolve(__dirname, '..');
const failures = [];

function run(executable, args, test) {
    console.log(`\n${test}`);
    const result = spawnSync(executable, [...args, path.join(__dirname, test)], {
        cwd: root,
        stdio: 'inherit',
    });
    if (result.error || result.status !== 0) {
        failures.push(`${test} (${result.error?.message ?? result.signal ?? result.status})`);
    }
}

for (const test of nodeTests) run(process.execPath, [], test);
for (const test of powershellTests) run('pwsh', ['-NoProfile', '-File'], test);

if (failures.length) {
    console.error(`\nFailed candidate regressions:\n${failures.join('\n')}`);
    process.exitCode = 1;
} else {
    console.log(`\nPassed ${nodeTests.length + powershellTests.length} candidate regression entries.`);
}
