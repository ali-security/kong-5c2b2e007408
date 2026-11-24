#!/usr/bin/perl
# CVE-2026-123007: a connection WINDOW_UPDATE must not be accepted while DATA frames are still queued
# if, counting the queued frames, it overflows the window.
#
# For each stream window WS the client lets nginx commit the whole stream window (most of it stuck in
# the output queue because the client does not read), then refunds WS on the connection window.
# Vulnerable nginx accepts the refund as long as WS <= committed bytes; fixed nginx also counts the
# queued bytes, so it starts rejecting at a smaller WS. Prints "first_reject=<KiB>".
use warnings; use strict;
use Test::More; use Socket qw(SOL_SOCKET SO_RCVBUF pack_sockaddr_in inet_aton);
use IO::Socket::INET;
BEGIN { use FindBin; chdir($FindBin::Bin); }
use lib $ENV{NGINX_TESTS_LIB};
use Test::Nginx qw(port); use Test::Nginx::HTTP2;

my $t = Test::Nginx->new()->has(qw/http http_v2/)->plan(1)
	->write_file_expand('nginx.conf', <<'CONF');
%%TEST_GLOBALS%%
daemon off;
events {}
http {
    %%TEST_GLOBALS_HTTP%%
    server {
        listen 127.0.0.1:8080 sndbuf=8k;
        http2 on;
        location / { }
    }
}
CONF
open my $fh, '>', $t->testdir() . '/big' or die; truncate $fh, 64 * 1024 * 1024; close $fh;
$t->run();

my $MAX = 2**31 - 1;
my (@res, $first); my $rej = 0;
for my $kb (map { $_ * 32 } 4 .. 32) {
	my $WS = $kb * 1024;
	my $sock = IO::Socket::INET->new(Proto => 'tcp') or die;
	setsockopt($sock, SOL_SOCKET, SO_RCVBUF, 4096);
	$sock->connect(pack_sockaddr_in(port(8080), inet_aton('127.0.0.1'))) or die "connect: $!";
	my $s = Test::Nginx::HTTP2->new(port(8080), socket => $sock);
	$s->h2_settings(0, 0x4 => $WS);
	$s->h2_window($MAX - 65535);
	$s->read(all => [{ type => 'SETTINGS', flags => 1 }], wait => 0.3);
	$s->new_stream({ path => '/big' });
	select undef, undef, undef, 0.7;
	$s->h2_window($WS);
	select undef, undef, undef, 0.5;
	my $n = () = $t->read_file('error.log') =~ /violated connection flow control/g;
	push @res, sprintf("%dK:%s", $kb, $n > $rej ? "REJ" : "acc");
	$first //= $kb if $n > $rej;
	$rej = $n;
	close $sock;
}
diag("WS -> WINDOW_UPDATE(WS): @res");
diag("first_reject=" . ($first // 'none'));
if ($ENV{SEAL_RESULTS}) { open my $r, '>>', $ENV{SEAL_RESULTS}; print $r "h2_123007_first_reject=" . ($first // 'none') . "\n"; }

$t->stop();
unlike($t->read_file('error.log'), qr/exited on signal|AddressSanitizer/, 'no crash');
