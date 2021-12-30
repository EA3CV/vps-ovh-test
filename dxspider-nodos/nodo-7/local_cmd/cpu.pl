#
# Usage: cpu
#
# CPU load and memory in use
# For use in DXSpider Node
#
# Kin EA3CV
#
# 20200205 v0.0
#

use IO::File;
use 5.10.1;
use strict;

my $cmd1;
my $cmd2;
my $total1 = 0;
my $total2 = 0;
my @out;

# Load CPU
open(CMD1, "ps -Ao pcpu,cmd --sort=-pcpu | grep 'perl' | grep -v 'grep'|");
while($cmd1 = <CMD1>) {
   chop $cmd1;
   my @in1 = split(/\s+/, $cmd1, 3);
   $total1 = $total1 + $in1[1];
}
$total1 = sprintf("Load CPU:   %.1f %", $total1);
close(CMD1);

# Mem Usage
open(CMD2, "ps aux | awk '{print \$2, \$4, \$11}' | sort -k2r | grep 'perl' | grep -v 'grep' |");

while($cmd2 = <CMD2>) {
   chop $cmd2;
   my @in2 = split(/\s+/, $cmd2, 3);
   $total2 = $total2 + $in2[1];
}
$total2 = sprintf("Mem Used:   %.1f %", $total2);
close(CMD2);

push @out, " ";
push @out, $total1;
push @out, $total2;
push @out, " ";

close(CMD);

return (1, @out)

