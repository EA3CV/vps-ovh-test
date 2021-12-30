#!/usr/bin/perl

#
# Genera un JSON con datos para estadísticas
#
# Usage: estadisticas_json <node>
# eg     estadisticas_json EA3CV-2
#
# Created by Kin EA3CV
# ea3cv@cronux.net
#
# v1.1
# 20211219
#

use strict;
use warnings;
use 5.10.1;
use Net::MQTT::Simple;

#my ($self, $node) = @_;

my @out;
my $mqtt = Net::MQTT::Simple->new("192.168.1.121:1883");

my ($dato1,$dato2,$dato3,$dato4,$dato5,$dato6,$dato7);


# Usuarios Locales Total

$dato1 = $main::routeroot->users;
$dato1 = '"users":"'. $dato1 . '"';

# Total Nodos

$dato2 = $main::routeroot->nodes;
$dato2 = '"nodes":"'. $dato2 . '"';

# Uptime

my ($nodes, $tot, $users, $maxlocalusers, $maxusers, $uptime, $localnodes) = Route::cluster();
my @array_uptime = split ' ', $uptime;
my @array_hora_minuto = split ':', @array_uptime[1];
my $min = (int(@array_uptime[0]) * 24 * 60) + (int(@array_hora_minuto[0]) * 60) + int(@array_hora_minuto[1]);

$dato3 =$min;
$dato3 = '"uptime":"'. $dato3 . '"';
# Total Nodos y Usuarios de la Red

$dato4 = Route::Node::count();
$dato5 = Route::User::count();

$dato4 = '"nodes_net":"'. $dato4 . '"';
$dato5 = '"users_net":"'. $dato5 . '"';


# CPU Load promedio 1 min y 5 min

my $info = `cat /proc/loadavg`;
my @fields = split (/ /, $info);

$dato6 = $fields[0];
$dato7 = $fields[1];

$dato6 = '"cpu1":"'. $dato6 . '"';
$dato7 = '"cpu5":"'. $dato7 . '"';

mqtt_send($dato1,$dato2,$dato3,$dato4,$dato5,$dato6,$dato7);


sub mqtt_send {
            my ($dato1,$dato2,$dato3,$dato4,$dato5,$dato6,$dato7) = @_;

            my $ts = time();

            my $payload = '{"ts":"' . $ts . '","node":"' . $main::mycall . '",'. $dato1 .','.  $dato2 . ','.  $dato3 . ','.  $dato4 . ','.  $dato5 . ','.  $dato6 . ','.  $dato7 . '}';

            $mqtt->publish("spider/stats", $payload);
            $mqtt->disconnect();
#           push @out, "$payload \n";
}

return (1, @out)
