<?php
defined('MOODLE_INTERNAL') || die();

if ($hassiteconfig) {
    $settings = new admin_settingpage('local_sisexample', get_string('pluginname', 'local_sisexample'));
    $settings->add(new admin_setting_configtext('local_sisexample/remoteurl',
        get_string('remoteurl', 'local_sisexample'), get_string('remoteurl_desc', 'local_sisexample'), '', PARAM_URL));
    $settings->add(new admin_setting_configtext('local_sisexample/greeting',
        get_string('greeting', 'local_sisexample'), get_string('greeting_desc', 'local_sisexample'), 'Hello', PARAM_TEXT));
    $ADMIN->add('localplugins', $settings);
}
