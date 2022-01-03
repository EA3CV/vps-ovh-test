# 
# Statistical packages processed in the DXSpider Node per day
#
# Use: stat_spots <YYYYMMDD>
# By default yesterday
#
# Created by EA3CV
#
# 20200402 v0.2
#

use Time::Piece;
use Time::Seconds;

my ($self, $line) = @_;
my @out;

if ( length($line) != 8 ) {
   my $time = Time::Piece->new;
   my $time  = $time - ONE_DAY;
   $line = $time->ymd("");
}

my $file = "/home/sysop/spider/local_data/spots/stat_spots_$line.txt";

open INPUT, '<', $file or die "Can not open input file: $!\n";

while (<INPUT>){
    push @out, sprintf " $_";
}

close INPUT;

return (1, @out)
