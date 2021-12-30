#!/usr/bin/perl

#
# Genera un JSON de usuarios y vecinos para estadisticas
#
# apt install libjson-maybexs-perl
#
# Usage: estadisticas_json <node>
# eg     estadisticas_json EA3CV-2
#
# Created by Kin EA3CV
# ea3cv@cronux.net
#
# v1.1
# 20211215
#

use strict;
use warnings;
use 5.10.1;
use Net::MQTT::Simple;

my ($self, $node) = @_;

my @out;

my $mqtt = Net::MQTT::Simple->new("192.168.1.121:1883");

my ($nodes, $tot, $users, $maxlocalusers, $maxusers, $uptime, $localnodes) = Route::cluster();

$localnodes = $main::routeroot->nodes;
$users = $main::routeroot->users;

# Tiempo uptime en segundos
$uptime = difft($main::starttime, ' ');
$uptime =~/([0-9h]+)\s+([0-9m]+)\s+([0-9s]+)/;
my $sec = $1*3600 + $2*60 + $3;

# Si tiempo > 4 min
if ($sec >= 240)
{
    my $payload = '{"nodo": "' . $node . '", "usuarios": "' . $users . '", "vecinos": "' . $localnodes . '"}';
    $mqtt->publish("spider/stats", $payload);
    $mqtt->disconnect();
#    push @out, "$payload   $uptime   $sec\n";
}

return (1, @out)
