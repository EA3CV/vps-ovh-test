#!/usr/bin/perl

#
# Genera un JSON de conexiones/desconexiones para estadisticas
#
# apt install libjson-maybexs-perl
#
# Usage: estadisticas_json <node>
# eg     estadisticas_json EA3CV-2
#
# Created by Kin EA3CV
# ea3cv@cronux.net
#
# v0.0
# 20201125
#

use strict;
use warnings;
use 5.10.1;
use Time::Piece;
use JSON::PP qw(encode_json decode_json);

$ENV{TZ} = "UTC";

my $server = $ARGV[0];

my $time = Time::Piece->new;
my $m = $time->mon();
$m = sprintf("%02d", $m);
my $y = $time->year("");

my $log = "/spider/local_data/log/$y/$m.dat";

open my $data, "-|", "/usr/bin/tail", "-n1", "-f", $log or die "could not start tail on $log: $!";

while (my $line = <$data>) {
        next unless ($line =~ /connected/);

        # 1590336672^DXCommand^EC3BH connected from 213.4.177.78
        # 1590336759^DXCommand^EC3BH disconnected
        # 1590337177^DXProt^IW9EDP-6 Disconnected
        # 1590337500^DXProt^IW9EDP-6 connected from 151.54.254.233
        # 1606290021^^OE3GCU has too many connections (3) at HA6DX,VE7CC-1,N6WS-6 - disconnected

        my @campos = split("\\^", $line);
        $campos[2] =~ m/(\w+||\w+\-\d+)\s(\w+)/;

        # Users
        if ($campos[1] eq "DXCommand") {
                if ($2 eq "connected") {
                        data_json($campos[0], $server, "user", $1, "Connect");
                } elsif ($2 eq "disconnected") {
                        data_json($campos[0], $server, "user", $1, "Disconnect");
                }
        # Nodes
        } elsif ($campos[1] eq "DXProt") {
                if ($2 eq "connected") {
                        data_json($campos[0], $server, "node", $1, "Connect");
                } elsif ($2 eq "Disconnected") {
                        data_json($campos[0], $server, "node", $1, "Disconnect");
                }
        }
}

close $data;

sub data_json {
        my $tstamp = shift;
	my $srv = shift;
        my $type = shift;
	my $call = shift;
        my $state = shift;

	my $output = '{"tstamp":"'.$tstamp.'","srv":"'.$srv.'","type":"'.$type.'","call":"'.$call.'","state":"'.$state.'"}';

	say $output;


# {"tstamp":"1606315863","srv":"EA3CV-2","type":"user","call":"EA3CV-8","state":"Connect"}
# {"tstamp":"1606315929","srv":"EA3CV-2","type":"user","call":"EA3CV-8","state":"Disconnect"}


}
