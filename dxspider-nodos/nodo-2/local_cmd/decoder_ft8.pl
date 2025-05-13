#!/usr/bin/perl

#
#  FT8 RBN Spot Decoder & Forwarder
#

#  Description:
#    This script connects via Telnet to a DXSpider cluster, logs in with a given
#    user and password, and sends a single DX command, then disconnects.
#
#  Requirements:
#    The target user in the DXSpider node must have the following configuration:
#      set/register <user>
#      set/password <user> <password>
#      set/privilege 2 <user>
#
#  Command format sent:
#    DX by <my_call> ip <my_ip> <freq> <call> <mode> <activity>
#
#  Author: Kin EA3CV <ea3cv@cronux.net>
#  License: GPLv3
#
#  Versión: 20250513 v1.2
#

use IO::Socket::IP;
use IO::Socket::INET;
use POSIX qw(strftime);
use strict;
use warnings;

my $rbn_host   = 'telnet.reversebeacon.net';
my $rbn_port   = 7001;
my $rbn_user   = 'EA3CV-52';

my $node_host  = '127.0.0.1';
my $node_port  = 7300;

my $node_user  = 'EA3CV-22';
my $node_pass  = 'muyd1f1c1l';

my %mode_table = (
    1  => 'CW',
    2  => 'SSB',
    3  => 'FM',
    4  => 'FT8',
    5  => 'FT4',
    6  => 'PSK',
    7  => 'RTTY',
    8  => 'SSTV',
);

my %activity_table = (
    1  => 'DME',
    2  => 'WCA',
    3  => 'WWFF',
    4  => 'BOTA',
    5  => 'COTA',
    6  => 'IOTA',
    7  => 'LOTA',
    8  => 'POTA',
    9  => 'SOTA',
    10 => 'DXpedition',
    11 => 'DCE',
    12 => 'DMVE',
    13 => 'DFE',
    14 => 'DVGE',
    15 => 'DEE',
    16 => 'Test Ignore',
);

sub is_valid_freq {
    my ($f) = @_;
    return (
        ($f >= 1810  && $f <= 2000)   ||
        ($f >= 3500  && $f <= 3800)   ||
        ($f >= 5351  && $f <= 5366)   ||
        ($f >= 7000  && $f <= 7300)   ||
        ($f >= 10100 && $f <= 10150)  ||
        ($f >= 14000 && $f <= 14350)  ||
        ($f >= 18068 && $f <= 18168)  ||
        ($f >= 21000 && $f <= 21450)  ||
        ($f >= 24890 && $f <= 24990)  ||
        ($f >= 28000 && $f <= 29700)  ||
        ($f >= 50000 && $f <= 52000)
    );
}

my $sock = IO::Socket::IP->new(
    PeerHost => $rbn_host,
    PeerPort => $rbn_port,
    Timeout  => 5,
) or die "No se pudo conectar a $rbn_host:$rbn_port - $!\n";

$sock->autoflush(1);
print $sock "$rbn_user\r\n";
print "[*] Conectado a RBN ($rbn_host:$rbn_port) como $rbn_user\n";

my %last_sent;

while (my $line = <$sock>) {
    chomp $line;

    while ($line =~ /\b([A-Z0-9]{8,11})\b/g) {
        my $full = uc($1);
        my $code = substr($full, -5);
        my $call = substr($full, 0, length($full) - 5);

        print "[+] Detectado: $call con código $code\n";

        # Antidupe: espera de 60 segundos entre spots del mismo call
        my $now = time;
        if (exists $last_sent{$call} && $now - $last_sent{$call} < 60) {
            print "[!] Ignorado por duplicado reciente: $call (esperando 60s)\n\n";
            next;
        }



        my ($freq, $mode, $activity) = decode_ft8($code);

        if ($mode =~ /UNKNOWN\(/ or $activity =~ /UNKNOWN\(/ or !is_valid_freq($freq)) {
            print "[!] Código no válido: modo=$mode actividad=$activity freq=$freq\n\n";
            next;
        }

        my $cmd = "DX by $node_user ip 149.202.47.39 $freq $call $mode $activity";
        print "[.] Preparando para enviar: $cmd\n";

        # Logging
        my $logfile = '/root/volumenes/dxspider/nodo-2/local_data/debug/robot/log.txt';
        my $timestamp = strftime "%Y%m%d-%H%M%S", localtime;
        open my $logfh, '>>', $logfile or warn "[!] No se pudo abrir el log: $!";
        print $logfh "$timestamp $call $freq $mode $activity\n";
        close $logfh;

        send_dxspider_command($node_host, $node_port, $node_user, $node_pass, $cmd);
        $last_sent{$call} = $now;
    }
}

sub decode_ft8 {
    my ($str) = @_;
    my $num = from_base36($str);

    if ($num & 0x01) {
        return (0, "UNKNOWN(LSB)", "UNKNOWN(LSB)");
    }

    my $packed = $num >> 1;

    my $activity_id =  $packed        & 0x1F;
    my $mode_id     = ($packed >> 5)  & 0x07;
    my $freq        = ($packed >> 8)  & 0xFFFF;

    my $mode_str     = $mode_table{$mode_id}     // "UNKNOWN($mode_id)";
    my $activity_str = $activity_table{$activity_id} // "UNKNOWN($activity_id)";

    return ($freq, $mode_str, $activity_str);
}

sub from_base36 {
    my $str = uc shift;
    my %value = map { $_ => $_ } (0..9);
    @value{'A'..'Z'} = (10..35);
    my $res = 0;
    $res = $res * 36 + $value{$_} for split //, $str;
    return $res;
}

sub send_dxspider_command {
    my ($host, $port, $user, $pass, $cmd) = @_;
    my $timeout = 10;

    my $sock = IO::Socket::INET->new(
        PeerHost => $host,
        PeerPort => $port,
        Proto    => 'tcp',
        Timeout  => $timeout,
    ) or do {
        print "[!] No se pudo conectar a $host:$port - $!\n";
        return;
    };

    $sock->autoflush(1);
    print $sock "$user\n"; sleep 1;
    print $sock "$pass\n"; sleep 1;

    my $buffer = '';
    my $start = time;
    while (1) {
        my $line = <$sock>;
        last unless defined $line;
        $buffer .= $line;
        last if $buffer =~ /dxspider\s*>\s*$/;
        die "[!] Timeout esperando prompt\n" if time() - $start > $timeout;
    }

    print "[TX] Enviando: $cmd\n";
    print $sock "$cmd\n";

    $buffer = '';
    $start = time;
    my $printing = 0;
    while (1) {
        my $line = <$sock>;
        last unless defined $line;
        $buffer .= $line;

        $printing = 1 if !$printing && $line !~ /^\s*$/ && $line !~ /dxspider\s*>/i;
        print $line if $printing && $line !~ /dxspider\s*>/i;

        last if $buffer =~ /dxspider\s*>\s*$/;
        die "[!] Timeout esperando respuesta\n" if time() - $start > $timeout;
    }

    print $sock "exit\n";
    close $sock;
    print "[*] Spot enviado y desconectado.\n";
}
