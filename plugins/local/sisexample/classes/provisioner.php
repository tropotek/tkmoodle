<?php
namespace local_sisexample;

defined('MOODLE_INTERNAL') || die();

/**
 * Creates, and checks, what this plugin needs on a site: a web service with a user
 * and token (stand-in for pairing with another system), an OAuth2 issuer (stand-in
 * for SSO), a role and a course category. Every step finds its object by a stable
 * key, so running it again changes nothing. Reads env and locked settings only;
 * institution defaults are applied after core install and are not visible here.
 */
class provisioner {
    public const CATEGORY = 'sisexample';
    public const ROLE = 'sisexample_manager';
    public const ROLE_CAPS = ['moodle/category:manage', 'moodle/course:create'];
    public const SERVICE = 'sisexample_service';
    public const SERVICE_FUNCTIONS = ['core_webservice_get_site_info', 'core_course_get_categories'];
    public const SERVICE_USER = 'sisexample_service';
    public const ISSUER = 'SIS Example SSO';

    /** @var string[] */
    private array $diffs = [];

    private function __construct(private bool $dryrun) {
    }

    /** @return string[] what was fixed */
    public static function apply(): array {
        $p = new self(false);
        $p->run();
        return $p->diffs;
    }

    /** @return string[] what differs; empty when the site is in sync */
    public static function check(): array {
        $p = new self(true);
        $p->run();
        return $p->diffs;
    }

    private function run(): void {
        $this->category();
        $this->role();
        $this->service();
        $this->sso();
    }

    private function change(string $what, callable $fix): void {
        $this->diffs[] = $what;
        if (!$this->dryrun) {
            $fix();
        }
    }

    private function category(): void {
        global $DB;
        if (!$DB->record_exists('course_categories', ['idnumber' => self::CATEGORY])) {
            $this->change('category ' . self::CATEGORY . ': missing', static function (): void {
                \core_course_category::create(['name' => 'SIS Example', 'idnumber' => self::CATEGORY]);
            });
        }
    }

    private function role(): void {
        global $DB;
        $roleid = $DB->get_field('role', 'id', ['shortname' => self::ROLE]);
        if (!$roleid) {
            $this->change('role ' . self::ROLE . ': missing', static function () use (&$roleid): void {
                $roleid = create_role('SIS Example manager', self::ROLE, 'Created by local_sisexample.');
                set_role_contextlevels($roleid, [CONTEXT_SYSTEM, CONTEXT_COURSECAT]);
            });
            if ($this->dryrun) {
                return;
            }
        }
        $contextid = \context_system::instance()->id;
        foreach (self::ROLE_CAPS as $cap) {
            $allowed = $DB->record_exists('role_capabilities',
                ['roleid' => $roleid, 'capability' => $cap, 'contextid' => $contextid, 'permission' => CAP_ALLOW]);
            if (!$allowed) {
                $this->change('role ' . self::ROLE . ": $cap not allowed", static function () use ($cap, $roleid, $contextid): void {
                    assign_capability($cap, CAP_ALLOW, $roleid, $contextid, true);
                });
            }
        }
    }

    private function service(): void {
        global $CFG, $DB;
        require_once($CFG->dirroot . '/webservice/lib.php');
        require_once($CFG->dirroot . '/user/lib.php');
        $ws = new \webservice();

        if (empty($CFG->enablewebservices)) {
            $this->change('web services: disabled', static fn() => set_config('enablewebservices', 1));
        }
        $protocols = array_filter(explode(',', (string)get_config('core', 'webserviceprotocols')));
        if (!in_array('rest', $protocols, true)) {
            $this->change('web service protocol rest: disabled',
                static fn() => set_config('webserviceprotocols', implode(',', array_merge($protocols, ['rest']))));
        }

        $service = $ws->get_external_service_by_shortname(self::SERVICE);
        if (!$service) {
            $this->change('service ' . self::SERVICE . ': missing', static function () use ($ws, &$service): void {
                $id = $ws->add_external_service((object)[
                    'name' => 'SIS Example', 'shortname' => self::SERVICE, 'enabled' => 1,
                    'restrictedusers' => 1, 'downloadfiles' => 0, 'uploadfiles' => 0,
                ]);
                $service = $ws->get_external_service_by_id($id);
            });
            if ($this->dryrun) {
                return;
            }
        }
        foreach (self::SERVICE_FUNCTIONS as $function) {
            if (!$ws->service_function_exists($function, $service->id)) {
                $this->change("service: function $function missing",
                    static fn() => $ws->add_external_function_to_service($function, $service->id));
            }
        }

        $user = $DB->get_record('user', ['username' => self::SERVICE_USER, 'deleted' => 0]);
        if (!$user) {
            $this->change('service user ' . self::SERVICE_USER . ': missing', static function () use (&$user, $CFG, $DB): void {
                $id = user_create_user([
                    'username' => self::SERVICE_USER, 'auth' => 'manual', 'confirmed' => 1,
                    'mnethostid' => $CFG->mnet_localhost_id, 'firstname' => 'SIS Example', 'lastname' => 'Service',
                    'email' => 'sisexample-service@example.invalid', 'password' => generate_password(32),
                ], true, false);
                $user = $DB->get_record('user', ['id' => $id]);
            });
            if ($this->dryrun) {
                return;
            }
        }
        if (!$ws->get_ws_authorised_user($service->id, $user->id)) {
            $this->change('service: user not authorised',
                static fn() => $ws->add_ws_authorised_user((object)['externalserviceid' => $service->id, 'userid' => $user->id]));
        }
        $hastoken = $DB->record_exists('external_tokens',
            ['externalserviceid' => $service->id, 'userid' => $user->id, 'tokentype' => EXTERNAL_TOKEN_PERMANENT]);
        if (!$hastoken) {
            $this->change('service token: missing', static function () use ($service, $user): void {
                $token = \core_external\util::generate_token(EXTERNAL_TOKEN_PERMANENT, $service, $user->id,
                    \context_system::instance(), 0, '', 'sisexample');
                mtrace('local_sisexample: service token created ****' . substr($token, -4)
                    . ' (cli/provision.php --show-token prints it)');
            });
        }
    }

    private function sso(): void {
        $baseurl = (string)getenv('SISEXAMPLE_SSO_ISSUER');
        $clientid = (string)getenv('SISEXAMPLE_SSO_CLIENT_ID');
        $secret = (string)getenv('SISEXAMPLE_SSO_SECRET');
        if ($baseurl === '' || $clientid === '' || $secret === '') {
            return;
        }

        $issuer = \core\oauth2\issuer::get_record(['name' => self::ISSUER]);
        if (!$issuer) {
            $this->change('oauth2 issuer: missing', static function () use ($baseurl, $clientid, $secret): void {
                $issuer = new \core\oauth2\issuer(0, (object)[
                    'name' => self::ISSUER, 'clientid' => $clientid, 'clientsecret' => $secret,
                    'baseurl' => $baseurl, 'enabled' => 1, 'image' => '',
                    'showonloginpage' => \core\oauth2\issuer::EVERYWHERE,
                    'loginscopes' => 'openid profile email',
                    'loginscopesoffline' => 'openid profile email offline_access',
                ]);
                $issuer->create();
                $root = rtrim($baseurl, '/') . '/protocol/openid-connect';
                foreach (['authorization_endpoint' => '/auth', 'token_endpoint' => '/token',
                          'userinfo_endpoint' => '/userinfo'] as $name => $path) {
                    (new \core\oauth2\endpoint(0, (object)[
                        'issuerid' => $issuer->get('id'), 'name' => $name, 'url' => $root . $path,
                    ]))->create();
                }
                foreach (['preferred_username' => 'username', 'email' => 'email',
                          'given_name' => 'firstname', 'family_name' => 'lastname'] as $external => $internal) {
                    (new \core\oauth2\user_field_mapping(0, (object)[
                        'issuerid' => $issuer->get('id'), 'externalfield' => $external, 'internalfield' => $internal,
                    ]))->create();
                }
            });
        } else if ($issuer->get('clientid') !== $clientid || $issuer->get('baseurl') !== $baseurl
                || $issuer->get('clientsecret') !== $secret) {
            $this->change('oauth2 issuer: differs from env', static function () use ($issuer, $baseurl, $clientid, $secret): void {
                $issuer->set('clientid', $clientid);
                $issuer->set('clientsecret', $secret);
                $issuer->set('baseurl', $baseurl);
                $issuer->update();
            });
        }

        if (!in_array('oauth2', explode(',', (string)get_config('core', 'auth')), true)) {
            $this->change('auth oauth2: disabled', static fn() => \core\plugininfo\auth::enable_plugin('oauth2', 1));
        }
    }
}
