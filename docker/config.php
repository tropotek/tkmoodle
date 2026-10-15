<?php
// Moodle config. Everything site-specific comes from env; the "locked" settings come
// from /sis/run/locked.php, which the entrypoint renders on every start.
// getenv() is called inline, never stored: a variable here becomes a Moodle global.
unset($CFG);
global $CFG;
$CFG = new stdClass();

$CFG->dbtype    = 'mysqli';
$CFG->dblibrary = 'native';
$CFG->dbhost    = getenv('DB_HOST') ?: 'db';
$CFG->dbname    = getenv('DB_NAME') ?: 'moodle';
$CFG->dbuser    = getenv('DB_USER') ?: 'moodle';
$CFG->dbpass    = getenv('DB_PASS') ?: '';
$CFG->prefix    = 'mdl_';
$CFG->dboptions = [
    'dbport'      => (int)(getenv('DB_PORT') ?: 3306),
    'dbcollation' => 'utf8mb4_unicode_ci',
];

$CFG->wwwroot  = getenv('WWWROOT') ?: 'http://localhost';
$CFG->dataroot = '/moodledata';
$CFG->admin    = 'admin';
$CFG->directorypermissions = 02777;

// Caddy sends unmatched paths to Moodle's router (r.php).
$CFG->routerconfigured = true;

// Plugins are installed by building an image, never from the admin UI.
$CFG->disableupdateautodeploy = true;
$CFG->disableupdatenotifications = true;

// curl may reach any host and port on a laptop, for local services; elsewhere Moodle's
// SSRF defaults stand.
if (getenv('SIS_ENV') === 'local') {
    $CFG->curlsecurityblockedhosts = '';
    $CFG->curlsecurityallowedport = '';
}

// A development box often runs a copy of production, so it never sends mail.
if (getenv('SIS_ENV') === 'development') {
    $CFG->noemailever = true;
}

// SMTP from .env when set, read-only in the admin UI then; empty leaves it to the admin.
if ((string)getenv('SMTP_HOSTS') !== '') {
    $CFG->smtphosts = getenv('SMTP_HOSTS');
}
if ((string)getenv('SMTP_USER') !== '') {
    $CFG->smtpuser = getenv('SMTP_USER');
}
if ((string)getenv('SMTP_PASS') !== '') {
    $CFG->smtppass = getenv('SMTP_PASS');
}
if ((string)getenv('SMTP_NOREPLY') !== '') {
    $CFG->noreplyaddress = getenv('SMTP_NOREPLY');
}

// Redis sessions when REDIS_HOST is set; Moodle's file sessions otherwise.
if ((string)getenv('REDIS_HOST') !== '') {
    $CFG->session_handler_class = '\core\session\redis';
    $CFG->session_redis_host = getenv('REDIS_HOST');
}

// An institution's locked settings come last, so they win over anything above.
if (is_file('/sis/run/locked.php')) {
    require '/sis/run/locked.php';
}

require_once(__DIR__ . '/lib/setup.php');
