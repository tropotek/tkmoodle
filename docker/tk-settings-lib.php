<?php
// Settings for an image: load settings.json files, validate and merge them, resolve
// ${VAR} references from the environment, and render the "locked" section as PHP
// for config.php. No Moodle dependency, so it is unit-tested with plain PHP.
declare(strict_types=1);

final class tk_settings_error extends RuntimeException {
}

const TK_SETTINGS_SECTIONS = ['defaults', 'locked'];
const TK_SETTINGS_GROUPS = ['core', 'plugins'];

/** Connection config comes from env only; a locked setting may not replace it. */
function tk_settings_is_connection_key(string $key): bool {
    return in_array($key, ['wwwroot', 'dataroot', 'prefix', 'admin'], true) || str_starts_with($key, 'db');
}

function tk_settings_load(string $path): array {
    if (!is_file($path)) {
        return [];
    }
    try {
        $data = json_decode((string)file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException $e) {
        throw new tk_settings_error("$path: invalid JSON: {$e->getMessage()}");
    }
    if (!is_array($data) || ($data !== [] && array_is_list($data))) {
        throw new tk_settings_error("$path: the top level must be an object");
    }
    tk_settings_validate($data, $path);
    return $data;
}

function tk_settings_validate(array $data, string $source): void {
    foreach ($data as $section => $groups) {
        if (!in_array($section, TK_SETTINGS_SECTIONS, true)) {
            throw new tk_settings_error("$source: unknown top-level key '$section' (expected defaults or locked)");
        }
        if (!is_array($groups)) {
            throw new tk_settings_error("$source: $section must be an object");
        }
        foreach ($groups as $group => $values) {
            if (!in_array($group, TK_SETTINGS_GROUPS, true)) {
                throw new tk_settings_error("$source: $section: unknown key '$group' (expected core or plugins)");
            }
            if (!is_array($values)) {
                throw new tk_settings_error("$source: $section.$group must be an object");
            }
            if ($group === 'core') {
                tk_settings_validate_leaves($values, "$source: $section.core");
                continue;
            }
            foreach ($values as $component => $leaves) {
                if (!preg_match('/^[a-z][a-z0-9]*_[a-z0-9_]+$/', (string)$component)) {
                    throw new tk_settings_error("$source: $section.plugins: invalid component '$component'");
                }
                if (!is_array($leaves)) {
                    throw new tk_settings_error("$source: $section.plugins.$component must be an object");
                }
                tk_settings_validate_leaves($leaves, "$source: $section.plugins.$component");
            }
        }
    }
}

function tk_settings_validate_leaves(array $leaves, string $where): void {
    foreach ($leaves as $key => $value) {
        if (!preg_match('/^[A-Za-z0-9_]+$/', (string)$key)) {
            throw new tk_settings_error("$where: invalid key '$key'");
        }
        if (!is_scalar($value)) {
            throw new tk_settings_error("$where.$key must be a scalar");
        }
    }
}

function tk_settings_merge(array $base, array $override): array {
    foreach ($override as $key => $value) {
        $base[$key] = is_array($value) && isset($base[$key]) && is_array($base[$key])
            ? tk_settings_merge($base[$key], $value)
            : $value;
    }
    return $base;
}

/** A scalar as Moodle stores it, with ${VAR} replaced; null when a referenced var is unset or empty. */
function tk_settings_value(bool|int|float|string $value, callable $getenv): ?string {
    if (is_bool($value)) {
        return $value ? '1' : '';
    }
    if (!is_string($value)) {
        return (string)$value;
    }
    $missing = false;
    $out = preg_replace_callback('/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/', static function (array $m) use ($getenv, &$missing): string {
        $v = $getenv($m[1]);
        if ($v === false || $v === null || $v === '') {
            $missing = true;
            return '';
        }
        return (string)$v;
    }, $value);
    return $missing ? null : $out;
}

function tk_settings_resolve(array $data, string $section, callable $getenv): array {
    $out = ['core' => [], 'plugins' => []];
    foreach ($data[$section]['core'] ?? [] as $key => $value) {
        $resolved = tk_settings_value($value, $getenv);
        if ($resolved !== null) {
            $out['core'][$key] = $resolved;
        }
    }
    foreach ($data[$section]['plugins'] ?? [] as $component => $leaves) {
        foreach ($leaves as $key => $value) {
            $resolved = tk_settings_value($value, $getenv);
            if ($resolved !== null) {
                $out['plugins'][$component][$key] = $resolved;
            }
        }
    }
    return $out;
}

function tk_settings_render_locked(array $resolved): string {
    $php = "<?php\n// Rendered at boot from the \"locked\" settings. Do not edit: it is rewritten on every start.\n";
    foreach ($resolved['core'] as $key => $value) {
        if (tk_settings_is_connection_key((string)$key)) {
            throw new tk_settings_error("locked.core.$key: connection settings come from env, not settings.json");
        }
        $php .= '$CFG->' . $key . ' = ' . var_export($value, true) . ";\n";
    }
    foreach ($resolved['plugins'] as $component => $leaves) {
        foreach ($leaves as $key => $value) {
            $php .= '$CFG->forced_plugin_settings[' . var_export($component, true) . '][' . var_export($key, true) . '] = '
                . var_export($value, true) . ";\n";
        }
    }
    return $php;
}
