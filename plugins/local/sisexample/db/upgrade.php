<?php
defined('MOODLE_INTERNAL') || die();

function xmldb_local_sisexample_upgrade(int $oldversion): bool {
    if ($oldversion < 2026101401) {
        // First version with provisioning: sites that installed 2026101400 get it here.
        \local_sisexample\provisioner::apply();
        upgrade_plugin_savepoint(true, 2026101401, 'local', 'sisexample');
    }
    return true;
}
