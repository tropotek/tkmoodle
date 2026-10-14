<?php
// Re-runs the plugin's provisioning.
//   provision.php              create or fix anything missing
//   provision.php --check      report differences only; exit 2 if there are any
//   provision.php --show-token print the service token
define('CLI_SCRIPT', true);

require(__DIR__ . '/../../../config.php');
require_once($CFG->libdir . '/clilib.php');

[$options] = cli_get_params(['check' => false, 'show-token' => false, 'help' => false], ['h' => 'help']);
if ($options['help']) {
    echo "Usage: php provision.php [--check] [--show-token]\n";
    exit(0);
}

\core\session\manager::set_user(get_admin());

if ($options['show-token']) {
    $token = $DB->get_field_sql(
        'SELECT t.token FROM {external_tokens} t
           JOIN {external_services} s ON s.id = t.externalserviceid
           JOIN {user} u ON u.id = t.userid
          WHERE s.shortname = ? AND u.username = ?',
        [\local_sisexample\provisioner::SERVICE, \local_sisexample\provisioner::SERVICE_USER], IGNORE_MULTIPLE);
    if (!$token) {
        cli_error('no token: run provision.php first', 1);
    }
    echo $token . "\n";
    exit(0);
}

$diffs = $options['check'] ? \local_sisexample\provisioner::check() : \local_sisexample\provisioner::apply();
foreach ($diffs as $diff) {
    echo ($options['check'] ? '~ ' : 'fixed: ') . $diff . "\n";
}
if (!$diffs) {
    echo "in sync\n";
}
exit($options['check'] && $diffs ? 2 : 0);
