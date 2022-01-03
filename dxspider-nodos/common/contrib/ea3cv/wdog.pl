#!/usr/bin/perl

#
# Check the status of the rbnspots.pl
# If no spots are received for 1 minute, restart the service
#
# Usage: wdog.pl server mode sysop
# eg     wdog.pl EA3CV-1 FT8 EA3CV
#
# Created by Kin EA3CV
# ea3cv@cronux.net
# v4.0
# 20200521
#

use strict;
use warnings;
use 5.10.1;
use Time::Piece;
use Time::Seconds;

$ENV{TZ} = "UTC";

my ($server, $mode, $sysop) = @ARGV;

my $time = Time::Piece->new;
my $d = $time->yday("")+1;
my $y = $time->year("");

my $log = "/spider/local_data/debug/$y/$d.dat";

open my $data, "-|", "/usr/bin/tail", "-f", $log or die "could not start tail on $log: $!";

my $n = 0;
my $timei = time ();

while (my $line = <$data>) {
	my $delta = time () - $timei;
	# Mas de 1000 paquetes o 2 min
    	if ( $line =~ /\^$mode/ && $line =~ /\SK1MMR/ ) {
        	last;
    	} elsif ($n > 1000 || $delta > 120) {
		&file($server,$sysop);
        	last;
	}
	$n++;
}

close $data;


sub file {
        my $srv = shift;
        my $sysop = shift;
        my $file = "/home/sysop/spider/cmd_import/$sysop";

        open(FILE, "> $file") || die "No pudo crearse: $!";
        print FILE "disc $srv\nconn $srv\n";
        close(FILE)
}
