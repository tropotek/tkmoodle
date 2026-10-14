<?php
// Plain page used to check that code edits are live in development.
require(__DIR__ . '/../../config.php');

header('Content-Type: text/plain');
echo "sisexample index v1\n";
echo 'greeting: ' . s((string)get_config('local_sisexample', 'greeting')) . "\n";
