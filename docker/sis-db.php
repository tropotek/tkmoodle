#!/usr/bin/env php
<?php
// Database probe for the entrypoint, over mysqli from env, so the image needs no
// database client.
//   sis-db.php wait <seconds>  exit 0 once a login succeeds; 1 on timeout
//   sis-db.php installed       exit 0 if Moodle is installed, 1 if the database is empty,
//                             3 if an install started but never finished (Moodle sets
//                             rolesactive as its last install step), 2 if the database
//                             cannot be queried
declare(strict_types=1);

mysqli_report(MYSQLI_REPORT_OFF);

function sis_db_connect(?string &$error): ?mysqli {
    $db = mysqli_init();
    $ok = @$db->real_connect(
        getenv('DB_HOST') ?: 'db',
        getenv('DB_USER') ?: 'moodle',
        getenv('DB_PASS') ?: '',
        getenv('DB_NAME') ?: 'moodle',
        (int)(getenv('DB_PORT') ?: 3306)
    );
    if (!$ok) {
        $error = $db->connect_error ?: 'connection failed';
        return null;
    }
    return $db;
}

$cmd = $argv[1] ?? '';
$error = null;

if ($cmd === 'wait') {
    $deadline = time() + (int)($argv[2] ?? 120);
    while (!sis_db_connect($error)) {
        if (time() >= $deadline) {
            fwrite(STDERR, "sis-db: database not reachable: $error\n");
            exit(1);
        }
        sleep(2);
    }
    echo "sis-db: database reachable\n";
    exit(0);
}

if ($cmd === 'installed') {
    $db = sis_db_connect($error);
    if (!$db) {
        fwrite(STDERR, "sis-db: $error\n");
        exit(2);
    }
    $result = $db->query("SHOW TABLES LIKE 'mdl\\_config'");
    if ($result === false) {
        fwrite(STDERR, "sis-db: {$db->error}\n");
        exit(2);
    }
    if ($result->num_rows === 0) {
        exit(1);
    }
    $result = $db->query("SELECT 1 FROM mdl_config WHERE name = 'rolesactive'");
    if ($result === false) {
        fwrite(STDERR, "sis-db: {$db->error}\n");
        exit(2);
    }
    exit($result->num_rows > 0 ? 0 : 3);
}

fwrite(STDERR, "usage: sis-db.php wait <seconds> | installed\n");
exit(64);
