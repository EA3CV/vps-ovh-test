#
# who : is online
# a complete list of stations connected
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#
# Modificado por EA3CV
#
# 20200531 v1.3
#

use List::MoreUtils 'first_index';
use Date::Calc qw(Today_and_Now Delta_YMDHMS Add_Delta_YMDHMS Delta_DHMS Date_to_Text);
use IO::File;
use 5.10.1;
use strict;

my $self = shift;
my $dxchan;
my @out;

push @out, " ";
push @out, "  List of connected Users:";
push @out, " ";
push @out, "  Callsign   Type         Started             Connection time    IP Address";
push @out, "  --------   ----------   -----------------   -----------------  ---------------";

foreach $dxchan ( sort {$a->call cmp $b->call} DXChannel::get_all ) {
    my $call = $dxchan->call();
        my $t = cldatetime($dxchan->startt);
        my $type = $dxchan->is_node ? "NODE" : "USER";
        my $sort = "    ";
        if ($dxchan->is_node) {
                $sort = "DXSP" if $dxchan->is_spider;
                $sort = "CLX " if $dxchan->is_clx;
                $sort = "DXNT" if $dxchan->is_dxnet;
                $sort = "AR-C" if $dxchan->is_arcluster;
                $sort = "AK1A" if $dxchan->is_ak1a;
        } else {
                $sort = "LOCL" if $dxchan->conn->isa('IntMsg');
                $sort = "WEB " if $dxchan->is_web;
                $sort = "EXT " if $dxchan->conn->isa('ExtMsg');
        }
        my $name = $dxchan->user->name || " ";
        my $ping = $dxchan->is_node && $dxchan != $main::me ? sprintf("%5.2f", $dxchan->pingave) : "     ";
        my $conn = $dxchan->conn;
        my $ip = '';
        if ($conn) {
                $ip = $dxchan->hostname;
                $ip = "AGW Port ($conn->{agwport})" if exists $conn->{agwport};
        }

# Obtener IP

        my $ipaddr;

        my $addr = $dxchan->hostname;
        if ($addr) {
            $ipaddr = $addr if is_ipaddr($addr);
#                $ipaddr = 'local' if $addr =~ /^127\./ || $addr =~ /^::[0-9a-f]+$/;
        }


my @lista_meses = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

my $hora = substr($t,12,2);
my $min = substr($t,14,2);
my $tt = substr($t,0,11);
my ($dia, $mes, $ano) = split('-', $tt);
my $i_mes = first_index { /$mes/ } @lista_meses;
$i_mes++;
my $today = [Today_and_Now()];
my $target = [$ano,$i_mes,$dia,$hora,$min,0];

my $sign = "until";
my $delta = Normalize_Delta_YMDHMS($today,$target);
if ($delta->[0] < 0)
{
    $sign = "since";
    $delta = Normalize_Delta_YMDHMS($target,$today);
}
my $fecha = sprintf(
    " %3d d %3d h %3d m",
    $delta->[2], $delta->[3], $delta->[4]
);

        if ($type eq "USER") {
                push @out, sprintf "  %-10s $type  $sort   $t $fecha   $ipaddr", $call;

        }
}

my $cmd1;
my $cmd2;
my $total1 = 0;
my $total2 = 0;

# Load CPU Perl
open(CMD1, "ps -Ao pcpu,cmd --sort=-pcpu | grep 'perl' | grep -v 'grep'|");
while($cmd1 = <CMD1>) {
   chop $cmd1;
   my @in1 = split(/\s+/, $cmd1, 3);
   $total1 = $total1 + $in1[1];
}
close(CMD1);

# Mem Usage
open(CMD2, "ps aux | awk '{print \$2, \$4, \$11}' | sort -k2r | grep 'perl' | grep -v 'grep'|");

while($cmd2 = <CMD2>) {
   chop $cmd2;
   my @in2 = split(/\s+/, $cmd2, 3);
   $total2 = $total2 + $in2[1];
}
close(CMD2);

my $all_users = scalar DXChannel::get_all_users();
my $uptime = main::uptime();

# CPU Load
my $info = `cat /proc/loadavg`;
my @fields = split (/ /, $info);
$fields[1] = $fields[1] * 100;

push @out, " ";
push @out, "  Users:  $all_users    Load:   $total1 %    CPU:  $fields[1] %    Mem:  $total2 %    Uptime: $uptime";
push @out, " ";


sub Normalize_Delta_YMDHMS
{
    my($date1,$date2) = @_;
    my(@delta);

    @delta = Delta_YMDHMS(@$date1,@$date2);
    while ($delta[1] < 0 or
           $delta[2] < 0 or
           $delta[3] < 0 or
           $delta[4] < 0 or
           $delta[5] < 0)
    {
        if ($delta[1] < 0) { $delta[0]--; $delta[1] += 12; }
        if ($delta[2] < 0)
        {
            $delta[1]--;
            @delta[2..5] = (0,0,0,0);
            @delta[2..5] = Delta_DHMS(Add_Delta_YMDHMS(@$date1,@delta),@$date2);
        }
        if ($delta[3] < 0) { $delta[2]--; $delta[3] += 24; }
        if ($delta[4] < 0) { $delta[3]--; $delta[4] += 60; }
        if ($delta[5] < 0) { $delta[4]--; $delta[5] += 60; }
    }
    return \@delta;
}

return (1, @out)
