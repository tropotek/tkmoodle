<?php
// Health endpoint: 200 once the entrypoint has finished booting, 503 before that.
header('Content-Type: text/plain');
header('X-Robots-Tag: noindex');
if (is_file('/tk/run/booted')) {
    echo "ok\n";
} else {
    http_response_code(503);
    echo "booting\n";
}
