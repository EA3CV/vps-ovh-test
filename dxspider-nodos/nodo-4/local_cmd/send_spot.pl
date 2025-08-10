#!/usr/bin/perl

#
# FT8 Encoder
#
# Kin EA3CV
# Version: 20250512 v1.1
#

use strict;
use warnings;

# Mode table (ID => name)
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

# Activity table (ID => name)
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
);

# Read arguments
my ($call, $freq, $mode_str, $activity_str) = @ARGV;

unless (defined $activity_str) {
    print "Usage: $0 CALL FREQ MODE ACTIVITY\n\n";

    print "    Frequency (kHz)    Modes    Activities\n";
    print "    ---------------    -----    ----------\n";

	my @bands = (
		[ '1810 -  2000', 'CW',     'DME'        ],
		[ '3500 -  3800', 'SSB',    'WCA'        ],
		[ '5351 -  5366', 'FM',     'WWFF'       ],
		[ '7000 -  7300', 'FT8',    'BOTA'       ],
		[ '10100 - 10150', 'FT4',   'COTA'       ],
		[ '14000 - 14350', 'PSK',   'IOTA'       ],
		[ '18068 - 18168', 'RTTY',  'LOTA'       ],
		[ '21000 - 21450', 'SSTV',  'POTA'       ],
		[ '24890 - 24990', '',      'SOTA'       ],
		[ '28000 - 29700', '',      'DXpedition' ],
		[ '50000 - 52000', '',      'DCE'        ],
		[ '',              '',      'DMVE'       ],
		[ '',              '',      'DFE'        ],
		[ '',              '',      'DVGE'       ],
		[ '',              '',      'DEE'        ],
	);

    for my $row (@bands) {
        my ($freq, $mode, $activity) = @$row;
        if ($freq eq '' && $mode eq '') {
            printf "%32s%s\n", '', $activity;
        } else {
            printf "    %-17s    %-7s  %-10s\n", $freq, $mode, $activity;
        }
    }

    print "\nNota:\n";
    print "Para permitir el envio correcto de spots a la red de clusteres,\n";
    print "debes estar registrado en el cluster:\n";
    print "  EA3CV-2\n";
    print "  dxcluster.cronux.net port 7300\n";
    print "Para registrarte, envia un correo a: ea3cv\@cronux.net\n";
    print "\nNote:\n";
    print "To allow proper spot forwarding to the cluster network,\n";
    print "you must be registered on the cluster:\n";
    print "  EA3CV-2\n";
    print "  dxcluster.cronux.net port 7300\n";
    print "To register, send an email to: ea3cv\@cronux.net\n\n";
    exit;
}

# Encode
my $code = encode_ft8($freq, $mode_str, $activity_str);
print "\nCadena para sustituir en WSJT-X/JTDX en lugar de tu indicativo: ${call}${code}\n";
print "String to substitute in WSJT-X/JTDX for your callsign: ${call}${code}\n";
print "\nUna vez actualizado el campo del indicativo, realiza 2 o 3 llamadas CQ\n";
print "Once the callsign field has been updated, make 2 or 3 CQ calls\n\n";

# Encode FT8
sub encode_ft8 {
    my ($freq, $mode_str, $activity_str) = @_;
    my %mode_rev     = reverse %mode_table;
    my %activity_rev = reverse %activity_table;

    my $mode_id     = $mode_rev{$mode_str}     // die "Unknown mode '$mode_str'";
    my $activity_id = $activity_rev{$activity_str} // die "Unknown activity '$activity_str'";

    die "freq must be < 131072" if $freq > 0x1FFFF;
    die "mode must be < 8"      if $mode_id > 0x07;
    die "activity must be < 32" if $activity_id > 0x1F;

    my $num = ($freq << 8) | ($mode_id << 5) | $activity_id;
    my $code = uc(to_base36($num));
    die "ERROR: Encoded value '$code' exceeds 5 characters (value=$num)" if length($code) > 5;

    return sprintf("%05s", $code);
}

# Decimal a Base36
sub to_base36 {
    my $num = shift;
    my @chars = ('0'..'9', 'A'..'Z');
    my $res = '';
    do {
        $res = $chars[$num % 36] . $res;
        $num = int($num / 36);
    } while ($num > 0);
    return $res;
}
