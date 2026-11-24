#!/usr/bin/perl
# Reproducers from the upstream fix commits for the rewrite / script / alias CVEs:
#   CVE-2026-9256  (3f135ae2) overlapping captures with "redirect" or arguments
#   CVE-2026-42945 (524977e7) is_args leaking escaping into later "set"
#   CVE-2026-42533 (7ac67898) map capture side effects / volatile map in a string expression
#   CVE-2026-15176 (ce1da789) alias mapping after rewrite changed the URI
# On fixed nginx every request gets a well-formed answer and no worker dies.
use warnings; use strict;
use Test::More;
BEGIN { use FindBin; chdir($FindBin::Bin); }
use lib $ENV{NGINX_TESTS_LIB};
use Test::Nginx qw(http_get);

my $t = Test::Nginx->new()->has(qw/http rewrite map/)->plan(7)
	->write_file_expand('nginx.conf', <<'CONF');
%%TEST_GLOBALS%%
daemon off;
events {}
http {
    %%TEST_GLOBALS_HTTP%%
    map $uri $map { ~(?<capture>.*) $capture; }
    map prefix:$capture $map_volatile { volatile; ~(?<capture>.*) $capture; }
    server {
        listen 127.0.0.1:8080;
        location /r1/ { rewrite ^/r1/((.*))$ http://127.0.0.1:8080/$1$2 redirect; return 200 foo; }
        location /r2/ { rewrite ^/r2/((.*))$ http://127.0.0.1:8080/?$1$2; return 200 foo; }
        location /e/  { rewrite ^(.*) /new?c=1; set $myvar $1; return 200 $myvar; }
        location /m/  { set $capture ""; set $temp "$capture $map"; return 200 $temp; }
        location /v/  { set $capture ""; set $temp "$map_volatile"; return 200 $temp; }
        location /fooooooooooooooooooooooooooooooooooooo/ {
            alias /bar/;
            rewrite ^/foo.*$ /x;
            return 200 "f=$request_filename";
        }
    }
}
CONF
$t->todo_alerts();   # fixed nginx logs "no buffer space in script copy" / alias alerts by design
$t->run();

my $plus = '+' x 300;
my $sp = '%20' x 200;
my $long = 'a' x 500;
my %code;
for (['r1', "/r1/$plus"], ['r2', "/r2/$plus"], ['e', "/e/$sp"], ['m', "/m/$long"], ['v', "/v/$long"],
	['alias', '/fooooooooooooooooooooooooooooooooooooo/1'])
{
	my $r = http_get($_->[1]) // '';
	($code{$_->[0]}) = $r =~ m{^HTTP/1\.\d (\d+)};
	$code{$_->[0]} //= 'none';
}
diag(join ' ', map { "$_=$code{$_}" } sort keys %code);

is($code{r1}, 302, 'CVE-2026-9256 redirect with overlapping captures');
is($code{r2}, 302, 'CVE-2026-9256 arguments with overlapping captures');
is($code{e}, 200, 'CVE-2026-42945 capture after rewrite with arguments');
is($code{m}, 500, 'CVE-2026-42533 map capture side effect refused');
is($code{v}, 500, 'CVE-2026-42533 volatile map length change refused');
is($code{alias}, 200, 'CVE-2026-15176 alias after rewrite');

$t->stop();
my $crash = $t->read_file('error.log') =~ /exited on signal|AddressSanitizer/ ? 1 : 0;
if ($ENV{SEAL_RESULTS}) { open my $r, '>>', $ENV{SEAL_RESULTS}; print $r "script_codes=" . join(',', map { "$_=$code{$_}" } sort keys %code) . " crash=$crash\n"; }
ok(!$crash, 'no worker crash');
