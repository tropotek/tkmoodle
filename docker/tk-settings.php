#!/usr/bin/env php
<?php
// Applies settings.json to the site.
//   tk-settings.php render [<out>]  write the "locked" settings as PHP for config.php
//   tk-settings.php defaults        set_config every "defaults" value (first install only)
// The institution file is merged with the optional host override; the override wins.
declare(strict_types=1);

require __DIR__ . '/tk-settings-lib.php';

$tkcmd = $argv[1] ?? '';
if ($tkcmd !== 'render' && $tkcmd !== 'defaults') {
    fwrite(STDERR, "usage: tk-settings.php render [<out>] | defaults\n");
    exit(64);
}
try {
    $tkdata = tk_settings_merge(
        tk_settings_load(getenv('TK_INSTITUTION_SETTINGS') ?: '/tk/institution/settings.json'),
        tk_settings_load(getenv('TK_OVERRIDE_SETTINGS') ?: '/tk/config/settings.json')
    );
    $tkgetenv = static fn(string $name) => getenv($name);

    if ($tkcmd === 'render') {
        $tkout = $argv[2] ?? '/tk/run/locked.php';
        $tkphp = tk_settings_render_locked(tk_settings_resolve($tkdata, 'locked', $tkgetenv));
        file_put_contents("$tkout.tmp", $tkphp);
        rename("$tkout.tmp", $tkout);
        echo "tk-settings: wrote $tkout\n";
        exit(0);
    }
    if ($tkcmd === 'defaults') {
        define('CLI_SCRIPT', true);
        require getenv('TK_MOODLE_CONFIG') ?: '/app/moodle/config.php';
        $tkdefaults = tk_settings_resolve($tkdata, 'defaults', $tkgetenv);
        foreach ($tkdefaults['core'] as $tkkey => $tkvalue) {
            set_config($tkkey, $tkvalue);
        }
        $tkcount = 0;
        foreach ($tkdefaults['plugins'] as $tkcomponent => $tkleaves) {
            foreach ($tkleaves as $tkkey => $tkvalue) {
                set_config($tkkey, $tkvalue, $tkcomponent);
                $tkcount++;
            }
        }
        printf("tk-settings: applied %d core and %d plugin defaults\n", count($tkdefaults['core']), $tkcount);
        exit(0);
    }
} catch (tk_settings_error $e) {
    fwrite(STDERR, "tk-settings: {$e->getMessage()}\n");
    exit(1);
}
