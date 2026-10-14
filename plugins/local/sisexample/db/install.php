<?php
defined('MOODLE_INTERNAL') || die();

function xmldb_local_sisexample_install(): bool {
    \local_sisexample\provisioner::apply();
    return true;
}
