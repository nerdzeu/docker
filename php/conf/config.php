<?php
namespace NERDZ\Core\Config;

define('DEBUG', 1);

class Variables
{
    public static $data = [
        // Database configuration
        // PostgreSQL hostname
        'POSTGRESQL_HOST'        => 'postgres',
        // PostgreSQL port
        'POSTGRESQL_PORT'        => '5432',
        // PostgreSQL database/scheme name
        'POSTGRESQL_DATA_NAME'   => 'test_db',

        // PostgreSQL username
        'POSTGRESQL_USER'        => 'test_db',
        // PostgreSQL password
        'POSTGRESQL_PASS'        => 'db_test',

        // Configuration of various requirements
        // Minimum username length (in characters)
        'MIN_LENGTH_USER'        => 2,
        // Minimum password length (in characters)
        'MIN_LENGTH_PASS'        => 6,
        // Minimum realname length (in characters)
        'MIN_LENGTH_NAME'        => 2,
        // Minimum surname  length (in characters)
        'MIN_LENGTH_SURNAME'     => 2,
        // Length of the CAPTCHA string (in chars)
        'CAPTCHA_LEVEL'          => 5,

        // Mail configuration
        // SMTP server username
        'SMTP_SERVER'            => 'smtp.gmail.com',
        // SMTP server port
        'SMTP_PORT'              => '587',
        // SMTP server username
        'SMTP_USER'              => 'WILLNOWORK',
        // SMTP server password
        'SMTP_PASS'              => 'WILLNOTWORK',

        // General configuration
        'SITE_NAME'              => 'NERD(Z)OCKER',

        // Domain configuration
        // Your NERDZ hostname. If you are running NERDZ on your
        // PC, use 'localhost'. Do NOT put the protocol (http/https).
        'SITE_HOST'              => 'primary.nerdz.eu',
        // The domain used to serve static data. If you are running
        // NERDZ on your PC, put an empty string.
        'STATIC_DOMAIN'          => 'static.primary.nerdz.eu',
        // The domain for the mobile version
        // The rules defined above also apply in this case
        'MOBILE_HOST'            => 'mobile.primary.nerdz.eu',

        // Minification configuration
        // NERDZ uses an automatic template minification system, this
        // means that every static file of a template is automagically
        // minified. This could lead to problems if you haven't a
        // proper installation of uglifyjs and csstidy. Disable the
        // minification if you don't need it or don't want to install
        // uglifyjs and csstidy.
        'MINIFICATION_ENABLED'   => true, // Default value: true
        // Specify the command used to minify JS/CSS files.
        // %path% will be replaced with the file to be minified.
        // Comment these options if the default commands are okay for you.
        //'MINIFICATION_CSS_CMD' => 'something-css %path%',
        //'MINIFICATION_JS_CMD'  => 'cat  %path%',

        // Misc configuration
        // True if you want to enable Redis session sharing. Disable it
        // if you don't have predis or a Redis server.
        'REDIS_ENABLED'          => false, // Default value: true
        'ISSUE_GIT_KEY'          => 'WILLNOWORK',
        // True if you want to connect to pushed (github.com/mcilloni/pushed) to serve push notifications to client apps like
        // NerdzMessenger (github.com/mcilloni/NerdzMessenger).
        'PUSHED_ENABLED'         => true,
        // PHP client supports only local pushed instances on IP (no UNIX sockets right now)
        // This parameter indicates IP version to use to connect to pushed (default: 6)
        'PUSHED_IP6'             => true,
        'PUSHED_PORT'            => 5667,
        'CAMO_KEY'               => '',
        'LOGIN_SSL_ONLY'         => false,
        'HTTPS_DOMAIN'          => 'primary.nerdz.eu'
    ];
}
