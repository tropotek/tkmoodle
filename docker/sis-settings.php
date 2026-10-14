#!/usr/bin/env php
<?php
// Applies settings.json to the site.
//   sis-settings.php render [<out>]  write the "locked" settings as PHP for config.php
//   sis-settings.php defaults        set_config every "defaults" value, once per site: it
//                                    records sis_defaults_applied and does nothing after that
// The institution file is merged with the optional host override; the override wins.
declare(strict_types=1);

require __DIR__ . '/sis-settings-lib.php';

$siscmd = $argv[1] ?? '';
if ($siscmd !== 'render' && $siscmd !== 'defaults') {
    fwrite(STDERR, "usage: sis-settings.php render [<out>] | defaults\n");
    exit(64);
}
try {
    $sisdata = sis_settings_merge(
        sis_settings_load(getenv('SIS_INSTITUTION_SETTINGS') ?: '/sis/institution/settings.json'),
        sis_settings_load(getenv('SIS_OVERRIDE_SETTINGS') ?: '/sis/config/settings.json')
    );
    $sisgetenv = static fn(string $name) => getenv($name);

    if ($siscmd === 'render') {
        $sisout = $argv[2] ?? '/sis/run/locked.php';
        $sisphp = sis_settings_render_locked(sis_settings_resolve($sisdata, 'locked', $sisgetenv));
        if (@file_put_contents("$sisout.tmp", $sisphp) === false || !@rename("$sisout.tmp", $sisout)) {
            throw new sis_settings_error("cannot write $sisout");
        }
        echo "sis-settings: wrote $sisout\n";
        exit(0);
    }
    if ($siscmd === 'defaults') {
        define('CLI_SCRIPT', true);
        require getenv('SIS_MOODLE_CONFIG') ?: '/app/moodle/config.php';
        if (get_config('core', 'sis_defaults_applied')) {
            echo "sis-settings: defaults already applied\n";
            exit(0);
        }
        $sisdefaults = sis_settings_resolve($sisdata, 'defaults', $sisgetenv);
        foreach ($sisdefaults['core'] as $siskey => $sisvalue) {
            set_config($siskey, $sisvalue);
        }
        $siscount = 0;
        foreach ($sisdefaults['plugins'] as $siscomponent => $sisleaves) {
            foreach ($sisleaves as $siskey => $sisvalue) {
                set_config($siskey, $sisvalue, $siscomponent);
                $siscount++;
            }
        }
        set_config('sis_defaults_applied', time());
        printf("sis-settings: applied %d core and %d plugin defaults\n", count($sisdefaults['core']), $siscount);
        exit(0);
    }
} catch (sis_settings_error $e) {
    fwrite(STDERR, "sis-settings: {$e->getMessage()}\n");
    exit(1);
}
