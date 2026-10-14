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

if (is_file('/sis/run/locked.php')) {
    require '/sis/run/locked.php';
}

require_once(__DIR__ . '/lib/setup.php');
