#!/usr/bin/perl

# 
# Makes the statistics of the packets received in the DXSpider Node
# and leave them at: /home/sysop/spider/local_data/spots/
# to be called by stat_spots.pl
# run from user sysop crontab
#
# Use: ./make_stat_spots.pl
#
# Created by EA3CV
#
# 20200401 v2.1
#

use 5.10.1;
use strict;
use Time::Piece;
use Time::Seconds;
use Data::Dumper;

#my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time - 60 * 60 * 24);
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time - 60 * 60 * 24);

$year += 1900;
$mon++;

my $y = $year;
my $d = sprintf("%03s", $yday);

my $time = Time::Piece->new;
my $time  = $time - ONE_DAY;
my $fecha = $time->ymd("");

# Convertir fecha entrada YYYYMMDD
#my $t = Time::Piece->strptime(@ARGV, '%Y%m%d');
#my $y = $t->year;
#my $d = $t->yday+1;
#$d = sprintf("%03s", $d);

my $log_dat = "/home/sysop/spider/local_data/debug/$y/$d.dat";

open INPUT, '<', $log_dat || die "Can not open input file: $!\n";
my $line;

my $pc11 = 0;
my $pc12 = 0;
my $pc16 = 0;
my $pc17 = 0;
my $pc18 = 0;
my $pc19 = 0;
my $pc20 = 0;
my $pc21 = 0;
my $pc22 = 0;
my $pc23 = 0;
my $pc24 = 0;
my $cc11 = 0;
my $pc39 = 0;
my $pc41 = 0;
my $pc50 = 0;
my $pc51 = 0;
my $pc61 = 0;
my $pc73 = 0;
my $pc92 = 0;
my $pc93 = 0;
my $skimmer = 0;
my $cw = 0;
my $rtty = 0;
my $psk = 0;
my $ft4 = 0;
my $ft8 =0;
my $beacon =0;

while($line = <INPUT>){
        chomp($line);

	#my @string = split(m[(?:firstpattern|secondpattern|thirdpattern)+], $string);
#	my @line = split(m[(?:\^| )+], $line);
        my @line = split(/\^/, $line);

#	my $PC_type  = $line[4];
#	my $mode     = $line[9];
#	my $skimmr   = $line[11];

        my $PC_type  = $line[1];
        my $mode     = $line[6];
        my $skimmr   = $line[8];

#	$PC_type = substr($PC_type, (index($PC_type, "C11", 0)-1), 4);
	$mode = substr($mode,0,6);
	$skimmr = substr($skimmr,0,6);

	# PC11
	if (substr($PC_type, index($PC_type, 'PC11', 0), 4) eq "PC11") {
		$pc11++;
	}

        # PC12
        if (substr($PC_type, index($PC_type, 'PC12', 0), 4) eq "PC12") {
                $pc12++;
        }

        # PC16
        if (substr($PC_type, index($PC_type, 'PC16', 0), 4) eq "PC16") {
                $pc16++;
        }

        # PC17
        if (substr($PC_type, index($PC_type, 'PC17', 0), 4) eq "PC17") {
                $pc17++;
        }

        # PC18
        if (substr($PC_type, index($PC_type, 'PC18', 0), 4) eq "PC18") {
                $pc18++;
        }

        # PC19
        if (substr($PC_type, index($PC_type, 'PC19', 0), 4) eq "PC19") {
                $pc19++;
        }

        # CC11
        if (substr($PC_type, index($PC_type, 'CC11', 0), 4) eq "CC11") {
                $cc11++;
        }

        # PC20
        if (substr($PC_type, index($PC_type, 'PC20', 0), 4) eq "PC20") {
                $pc20++;
        }

        # PC21
        if (substr($PC_type, index($PC_type, 'PC21', 0), 4) eq "PC21") {
                $pc21++;
        }

        # PC22
        if (substr($PC_type, index($PC_type, 'PC22', 0), 4) eq "PC22") {
                $pc22++;
        }

        # PC23
        if (substr($PC_type, index($PC_type, 'PC23', 0), 4) eq "PC23") {
                $pc23++;
        }

        # PC24
        if (substr($PC_type, index($PC_type, 'PC24', 0), 4) eq "PC24") {
                $pc24++;
        }

        # PC39
        if (substr($PC_type, index($PC_type, 'PC39', 0), 4) eq "PC39") {
                $pc39++;
        }

        # PC41
        if (substr($PC_type, index($PC_type, 'PC41', 0), 4) eq "PC41") {
                $pc41++;
        }

        # PC50
        if (substr($PC_type, index($PC_type, 'PC50', 0), 4) eq "PC50") {
                $pc50++;
        }

        # PC51
        if (substr($PC_type, index($PC_type, 'PC51', 0), 4) eq "PC51") {
                $pc51++;
        }

        # PC61
        if (substr($PC_type, index($PC_type, 'PC61', 0), 4) eq "PC61") {
                $pc61++;
        }

        # PC73
        if (substr($PC_type, index($PC_type, 'PC73', 0), 4) eq "PC73") {
                $pc73++;
        }

        # PC92
        if (substr($PC_type, index($PC_type, 'PC92', 0), 4) eq "PC92") {
                $pc92++;
        }

        # PC93
        if (substr($PC_type, index($PC_type, 'PC93', 0), 4) eq "PC93") {
                $pc93++;
        }

        # SKIMMER 
        if ($skimmr eq "SK1MMR") {
                $skimmer++;

		if ($mode eq "CW    ") {
#			$mode = substr($mode, index($mode, "BEACON", 0), 6);
#			if ($mode eq ("BEACON")) {
#				$beacon++;
#			} else {
				$cw++
#			}
                } elsif ($mode eq "RTTY  ") {
			$rtty++;
                } elsif ($mode eq ("PSK31 " || "PSK64 " || "PSK125")) {
                        $psk++;
                } elsif ($mode eq "FT8   ") {
                        $ft8++;
                } elsif ($mode eq "FT4   ") {
                        $ft4++;
		}
	}
}

my $human = ($pc11 - $skimmer);
my $total = ($pc11 + $cc11 + $pc12 + $pc16 + $pc17 + $pc18 + $pc19 + $pc20 + $pc21 + $pc22 + $pc23 + $pc24 + $pc39 + $pc41 + $pc50 +$pc51 + $pc61 + $pc73 + $pc92 + $pc93);

open(LOG,">/home/sysop/spider/local_data/spots/stat_spots_$fecha.txt");

printf LOG "\n";
printf LOG "Packages generated during the day: $fecha\n";
printf LOG "\n";
printf LOG "          Totals     Humans   Skimmers\n";
printf LOG "        --------   --------   --------\n";
printf LOG ("PC11:   %8s   %8s   %8s\n", $pc11, $human, $skimmer);
printf LOG "\n";

printf LOG ("CC11:   %8s      PC39:   %8s\n", $cc11, $pc39);
printf LOG ("PC12:   %8s      PC41:   %8s\n", $pc12, $pc41);
printf LOG ("PC16:   %8s      PC50:   %8s\n", $pc16, $pc50);
printf LOG ("PC17:   %8s      PC51:   %8s\n", $pc17, $pc51);
printf LOG ("PC18:   %8s      PC61:   %8s\n", $pc18, $pc61);
printf LOG ("PC19:   %8s      PC73:   %8s\n", $pc19, $pc73);
printf LOG ("PC20:   %8s      PC92:   %8s\n", $pc20, $pc92);
printf LOG ("PC21:   %8s      PC93:   %8s\n", $pc21, $pc93);
printf LOG ("PC22:   %8s\n", $pc22);
printf LOG ("PC23:   %8s\n", $pc23);
printf LOG ("PC24:   %8s\n", $pc24);
printf LOG "\n";
printf LOG " SKIMMER        CW       PSK      RTTY       FT4       FT8\n";
printf LOG "--------  --------  --------  --------  --------  --------\n";
printf LOG ("%8s  %8s  %8s  %8s  %8s  %8s  %8s\n\n", $skimmer, $cw, $psk, $rtty, $ft4, $ft8);

printf LOG ("TOTAL:  %8s\n\n", $total);

close LOG;
close INPUT;
