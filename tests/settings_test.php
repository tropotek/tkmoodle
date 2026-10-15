<?php
// Tests for the settings renderer (docker/sis-settings*.php). Run: php tests/settings_test.php
declare(strict_types=1);

require __DIR__ . '/../docker/sis-settings-lib.php';

$failures = 0;
function check(string $name, bool $ok): void {
    global $failures;
    echo ($ok ? 'ok   ' : 'FAIL ') . $name . "\n";
    if (!$ok) {
        $failures++;
    }
}
function throws(callable $f, string $needle = ''): bool {
    try {
        $f();
        return false;
    } catch (sis_settings_error $e) {
        return $needle === '' || str_contains($e->getMessage(), $needle);
    }
}
function tmpjson(string $json): string {
    $p = tempnam(sys_get_temp_dir(), 'sis');
    file_put_contents($p, $json);
    return $p;
}
$env = ['HOST' => 'sso.example.com', 'EMPTY' => '', 'ODD' => "a'b\$c\\d?>e"];
$getenv = static fn(string $n) => $env[$n] ?? false;

// load
check('load: missing file is empty', sis_settings_load('/nonexistent/settings.json') === []);
check('load: invalid JSON throws', throws(fn() => sis_settings_load(tmpjson('{nope')), 'invalid JSON'));
check('load: top-level list throws', throws(fn() => sis_settings_load(tmpjson('[1]')), 'object'));
check('load: empty object is empty', sis_settings_load(tmpjson('{}')) === []);

// validate
check('validate: unknown top-level key', throws(fn() => sis_settings_validate(['extra' => []], 'x'), "unknown top-level key 'extra'"));
check('validate: unknown group', throws(fn() => sis_settings_validate(['locked' => ['theme' => []]], 'x'), "unknown key 'theme'"));
check('validate: array leaf', throws(fn() => sis_settings_validate(['defaults' => ['core' => ['a' => [1]]]], 'x'), 'must be a scalar'));
check('validate: null leaf', throws(fn() => sis_settings_validate(['defaults' => ['core' => ['a' => null]]], 'x'), 'must be a scalar'));
check('validate: bad component', throws(fn() => sis_settings_validate(['locked' => ['plugins' => ['Bad-Name' => ['a' => '1']]]], 'x'), 'invalid component'));
check('validate: bad key', throws(fn() => sis_settings_validate(['locked' => ['core' => ['a b' => '1']]], 'x'), 'invalid key'));
check('validate: key starting with a digit', throws(fn() => sis_settings_validate(['locked' => ['core' => ['1abc' => 'x']]], 'x'), 'invalid key'));
check('validate: numeric key', throws(fn() => sis_settings_validate(['locked' => ['core' => ['0' => 'x']]], 'x')));
check('validate: list under core', throws(fn() => sis_settings_validate(['locked' => ['core' => ['x', 'y']]], 'x'), 'must be an object'));
check('validate: list under a component', throws(fn() => sis_settings_validate(['locked' => ['plugins' => ['local_x' => ['a']]]], 'x'), 'must be an object'));
check('validate: good data passes', !throws(fn() => sis_settings_validate(['defaults' => ['core' => ['timezone' => 'UTC'], 'plugins' => ['theme_boost_union' => ['x' => 1]]]], 'x')));

// reserved keys: refused in either section when a file loads, before any ${VAR} is resolved
$reserved = ['wwwroot', 'dataroot', 'prefix', 'admin', 'dbpass', 'dbhost', 'dirroot', 'libdir', 'tempdir',
    'backuptempdir', 'cachedir', 'localcachedir', 'localrequestdir', 'themedir', 'langotherroot', 'langlocalroot',
    'forced_plugin_settings', 'config_php_settings'];
foreach ($reserved as $k) {
    check("validate refuses reserved key: $k", throws(fn() => sis_settings_validate(['locked' => ['core' => [$k => 'x']]], 'f.json'), "locked.core.$k"));
}
check('validate refuses a reserved key in defaults', throws(fn() => sis_settings_validate(['defaults' => ['core' => ['wwwroot' => 'x']]], 'f.json'), 'defaults.core.wwwroot'));
check('validate refuses a reserved key behind an unset ${VAR}', throws(fn() => sis_settings_validate(['locked' => ['core' => ['dbhost' => '${NOT_SET}']]], 'f.json'), 'locked.core.dbhost'));
check('load refuses a reserved key, naming the file', throws(fn() => sis_settings_load(tmpjson('{"defaults":{"core":{"tempdir":"/x"}}}')), 'defaults.core.tempdir'));
check('validate allows a plugin setting named like a reserved key', !throws(fn() => sis_settings_validate(['locked' => ['plugins' => ['local_x' => ['wwwroot' => 'x']]]], 'f.json')));

// merge
$m = sis_settings_merge(
    ['defaults' => ['core' => ['a' => '1', 'b' => '2']], 'locked' => ['core' => ['c' => '3']]],
    ['defaults' => ['core' => ['b' => 'B']]]
);
check('merge: override wins', $m['defaults']['core']['b'] === 'B');
check('merge: siblings kept', $m['defaults']['core']['a'] === '1' && $m['locked']['core']['c'] === '3');

// resolve
$data = ['locked' => [
    'core' => ['flag' => true, 'off' => false, 'num' => 5, 'url' => 'https://${HOST}/x', 'gone' => '${MISSING}', 'blank' => '${EMPTY}'],
    'plugins' => ['local_sisexample' => ['remoteurl' => '${HOST}', 'skip' => '${MISSING}']],
]];
$r = sis_settings_resolve($data, 'locked', $getenv);
check('resolve: true is "1"', $r['core']['flag'] === '1');
check('resolve: false is ""', $r['core']['off'] === '');
check('resolve: int is string', $r['core']['num'] === '5');
check('resolve: embedded var', $r['core']['url'] === 'https://sso.example.com/x');
check('resolve: unset var skips key', !array_key_exists('gone', $r['core']));
check('resolve: empty var skips key', !array_key_exists('blank', $r['core']));
check('resolve: plugin var', $r['plugins']['local_sisexample']['remoteurl'] === 'sso.example.com');
check('resolve: plugin unset skips key', !array_key_exists('skip', $r['plugins']['local_sisexample']));
check('resolve: missing section is empty', sis_settings_resolve([], 'defaults', $getenv) === ['core' => [], 'plugins' => []]);

// render
$php = sis_settings_render_locked(['core' => ['authpreventaccountcreation' => '1', 'odd' => $env['ODD']], 'plugins' => ['local_sisexample' => ['remoteurl' => 'https://x']]]);
$CFG = new stdClass();
eval('?>' . $php);
check('render: core key set', $CFG->authpreventaccountcreation === '1');
check('render escapes hostile values', $CFG->odd === $env['ODD']);
check('render: plugin key forced', $CFG->forced_plugin_settings['local_sisexample']['remoteurl'] === 'https://x');
foreach (['wwwroot', 'dataroot', 'prefix', 'admin', 'dbpass', 'dbhost', 'tempdir', 'forced_plugin_settings'] as $k) {
    check("render refuses connection keys: $k", throws(fn() => sis_settings_render_locked(['core' => [$k => 'x'], 'plugins' => []]), $k));
}

// CLI: exit codes the entrypoint relies on
function cli(array $args, array $env = []): int {
    $cmd = 'php ' . escapeshellarg(__DIR__ . '/../docker/sis-settings.php');
    foreach ($args as $arg) {
        $cmd .= ' ' . escapeshellarg($arg);
    }
    $p = proc_open($cmd, [1 => ['file', '/dev/null', 'w'], 2 => ['file', '/dev/null', 'w']], $pipes, null, $env + getenv());
    return proc_close($p);
}
check('cli: unknown command exits 64', cli(['nonsense']) === 64);
$out = sys_get_temp_dir() . '/sis-locked-' . getmypid() . '.php';
check('cli: invalid override exits 1', cli(['render', $out], ['SIS_OVERRIDE_SETTINGS' => tmpjson('{bad')]) === 1);
check('cli: no output written on error', !file_exists($out));
check('cli: valid render exits 0', cli(['render', $out], ['SIS_INSTITUTION_SETTINGS' => tmpjson('{"locked":{"core":{"x":"1"}}}')]) === 0 && is_file($out));
@unlink($out);
check('cli: unwritable output exits 1', cli(['render', '/nonexistent-dir/locked.php']) === 1);

exit($failures ? 1 : 0);
