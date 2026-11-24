#!/usr/bin/perl
# CVE-2026-49975 ("HTTP/2 bomb"): nginx accepted any number of request header lines. The fix
# (nginx 36569416, max_headers, default 1000) refuses more than 1000, over HTTP/1.1 and HTTP/2.
use warnings; use strict;
use Test::More;
BEGIN { use FindBin; chdir($FindBin::Bin); }
use lib $ENV{NGINX_TESTS_LIB};
use Test::Nginx qw(http); use Test::Nginx::HTTP2;

my $t = Test::Nginx->new()->has(qw/http http_v2/)->plan(1)
	->write_file_expand('nginx.conf', <<'CONF');
%%TEST_GLOBALS%%
daemon off;
events {}
http {
    %%TEST_GLOBALS_HTTP%%
    server {
        listen 127.0.0.1:8080;
        http2 on;
        large_client_header_buffers 8 16k;  # room for 1100 lines, so only the count limit applies
        location / { return 200 ok; }
    }
}
CONF
$t->run();

my $hdrs = join '', map { "X-$_: 1\r\n" } 1 .. 1100;
my $r = http("GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n$hdrs\r\n") // '';
my ($h1) = $r =~ m{^HTTP/1\.\d (\d+)};

my $s = Test::Nginx::HTTP2->new();
my $sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET', mode => 0 }, { name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/', mode => 0 }, { name => ':authority', value => 'localhost', mode => 3 },
	map { +{ name => "x-$_", value => '1', mode => 4 } } 1 .. 1100 ] });  # literal, no indexing
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
my ($f) = grep { $_->{type} eq "HEADERS" } @$frames;
my $h2 = $f ? $f->{headers}{":status"} : "none:" . join(",", map { "$_->{type}" . ($_->{code} // "") } @$frames);

diag("1100 header lines: HTTP/1.1=" . ($h1 // 'none') . " HTTP/2=$h2");
if ($ENV{SEAL_RESULTS}) { open my $o, '>>', $ENV{SEAL_RESULTS}; print $o "max_headers_1100 h1=" . ($h1 // 'none') . " h2=$h2\n"; }
$t->stop();
unlike($t->read_file('error.log'), qr/exited on signal/, 'no crash');
