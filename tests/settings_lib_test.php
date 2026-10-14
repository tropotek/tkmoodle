<?php
// Unit tests for docker/tk-settings-lib.php. Run: php tests/settings_lib_test.php
declare(strict_types=1);

require __DIR__ . '/../docker/tk-settings-lib.php';

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
    } catch (tk_settings_error $e) {
        return $needle === '' || str_contains($e->getMessage(), $needle);
    }
}
function tmpjson(string $json): string {
    $p = tempnam(sys_get_temp_dir(), 'tks');
    file_put_contents($p, $json);
    return $p;
}
$env = ['HOST' => 'sso.example.com', 'EMPTY' => '', 'ODD' => "a'b\$c\\d?>e"];
$getenv = static fn(string $n) => $env[$n] ?? false;

// load
check('load: missing file is empty', tk_settings_load('/nonexistent/settings.json') === []);
check('load: invalid JSON throws', throws(fn() => tk_settings_load(tmpjson('{nope')), 'invalid JSON'));
check('load: top-level list throws', throws(fn() => tk_settings_load(tmpjson('[1]')), 'object'));
check('load: empty object is empty', tk_settings_load(tmpjson('{}')) === []);

// validate
check('validate: unknown top-level key', throws(fn() => tk_settings_validate(['extra' => []], 'x'), "unknown top-level key 'extra'"));
check('validate: unknown group', throws(fn() => tk_settings_validate(['locked' => ['theme' => []]], 'x'), "unknown key 'theme'"));
check('validate: array leaf', throws(fn() => tk_settings_validate(['defaults' => ['core' => ['a' => [1]]]], 'x'), 'must be a scalar'));
check('validate: null leaf', throws(fn() => tk_settings_validate(['defaults' => ['core' => ['a' => null]]], 'x'), 'must be a scalar'));
check('validate: bad component', throws(fn() => tk_settings_validate(['locked' => ['plugins' => ['Bad-Name' => ['a' => '1']]]], 'x'), 'invalid component'));
check('validate: bad key', throws(fn() => tk_settings_validate(['locked' => ['core' => ['a b' => '1']]], 'x'), 'invalid key'));
check('validate: good data passes', !throws(fn() => tk_settings_validate(['defaults' => ['core' => ['timezone' => 'UTC'], 'plugins' => ['theme_boost_union' => ['x' => 1]]]], 'x')));

// merge
$m = tk_settings_merge(
    ['defaults' => ['core' => ['a' => '1', 'b' => '2']], 'locked' => ['core' => ['c' => '3']]],
    ['defaults' => ['core' => ['b' => 'B']]]
);
check('merge: override wins', $m['defaults']['core']['b'] === 'B');
check('merge: siblings kept', $m['defaults']['core']['a'] === '1' && $m['locked']['core']['c'] === '3');

// resolve
$data = ['locked' => [
    'core' => ['flag' => true, 'off' => false, 'num' => 5, 'url' => 'https://${HOST}/x', 'gone' => '${MISSING}', 'blank' => '${EMPTY}'],
    'plugins' => ['local_tkexample' => ['remoteurl' => '${HOST}', 'skip' => '${MISSING}']],
]];
$r = tk_settings_resolve($data, 'locked', $getenv);
check('resolve: true is "1"', $r['core']['flag'] === '1');
check('resolve: false is ""', $r['core']['off'] === '');
check('resolve: int is string', $r['core']['num'] === '5');
check('resolve: embedded var', $r['core']['url'] === 'https://sso.example.com/x');
check('resolve: unset var skips key', !array_key_exists('gone', $r['core']));
check('resolve: empty var skips key', !array_key_exists('blank', $r['core']));
check('resolve: plugin var', $r['plugins']['local_tkexample']['remoteurl'] === 'sso.example.com');
check('resolve: plugin unset skips key', !array_key_exists('skip', $r['plugins']['local_tkexample']));
check('resolve: missing section is empty', tk_settings_resolve([], 'defaults', $getenv) === ['core' => [], 'plugins' => []]);

// render
$php = tk_settings_render_locked(['core' => ['authpreventaccountcreation' => '1', 'odd' => $env['ODD']], 'plugins' => ['local_tkexample' => ['remoteurl' => 'https://x']]]);
$CFG = new stdClass();
eval('?>' . $php);
check('render: core key set', $CFG->authpreventaccountcreation === '1');
check('render escapes hostile values', $CFG->odd === $env['ODD']);
check('render: plugin key forced', $CFG->forced_plugin_settings['local_tkexample']['remoteurl'] === 'https://x');
foreach (['wwwroot', 'dataroot', 'prefix', 'admin', 'dbpass', 'dbhost'] as $k) {
    check("render refuses connection keys: $k", throws(fn() => tk_settings_render_locked(['core' => [$k => 'x'], 'plugins' => []]), $k));
}

exit($failures ? 1 : 0);
