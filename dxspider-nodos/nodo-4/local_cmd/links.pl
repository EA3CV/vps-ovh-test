#
# links : which are active
# a complete list of currently connected linked nodes
#
# Created by Iain Philipps G0RDI, based entirely on
# who.pl, which is Copyright (c) 1999 Dirk Koopman G1TLH
# and subsequently plagerized by K1XX.
#
# Modificado por EA3CV
#
# 20200328 v0.1
#

use List::MoreUtils 'first_index';
use Date::Calc qw(Today_and_Now Delta_YMDHMS Add_Delta_YMDHMS Delta_DHMS Date_to_Text);

my $self = shift;
my $dxchan;
my @out;
my $nowt = time;

push @out, " ";
push @out, " Lista de Nodos conectados:";
push @out, " ";
push @out, " Callsign   Type  Started            Connection time     PC92  IP Address";
push @out, " --------   ----  -----------------  ------------------  ----  ---------------";

foreach $dxchan ( sort {$a->call cmp $b->call} DXChannel::get_all_nodes ) {
	my $call = $dxchan->call();
	next if $dxchan == $main::me;
	my $t = cldatetime($dxchan->startt);
	my $sort;
	my $name = $dxchan->user->name || " ";
	my ($fin, $fout, $pc92) = (' ', ' ', ' ');
	if ($dxchan->do_pc9x) {
		$pc92 = 'Y';
	} else {
		my $f;
		if ($f = $dxchan->inroutefilter) {
			$fin = $dxchan->inroutefilter =~ /node_default/ ? 'D' : 'Y';
		}
		if ($f = $dxchan->routefilter) {
			$fout = $dxchan->routefilter =~ /node_default/ ? 'D' : 'Y';
		}
	}

	$sort = "DXSP" if $dxchan->is_spider;
	$sort = "CLX " if $dxchan->is_clx;
	$sort = "DXNT" if $dxchan->is_dxnet;
	$sort = "AR-C" if $dxchan->is_arcluster;
	$sort = "AK1A" if $dxchan->is_ak1a;

        $sort = "LOCL" if $dxchan->conn->isa('IntMsg');
        $sort = "WEB " if $dxchan->is_web;
        $sort = "EXT " if $dxchan->conn->isa('ExtMsg');

	my $ipaddr;

	my $addr = $dxchan->hostname;
	if ($addr) {
	    $ipaddr = $addr if is_ipaddr($addr);
		$ipaddr = 'local' if $addr =~ /^127\./ || $addr =~ /^::[0-9a-f]+$/;
	}
	$ipaddr = 'ax25' if $dxchan->conn->ax25;

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

push @out, sprintf " %-10s $sort  $t $fecha    $pc92    $ipaddr", $call;
}

my $all_nodes = scalar DXChannel::get_all_nodes();
my $uptime = main::uptime();

push @out, " ";
push @out, " Nodos:  $all_nodes";
push @out, " Uptime: $uptime";
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




