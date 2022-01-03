#!/usr/bin/perl

#
# Usage: swap
#
# Total swap and used swap.
# Intended for use in the DXSpider Node
#
# Kin EA3CV
#
# 20200408 v0.0
#

use IO::File;
use 5.10.1;
use strict;

my @in1;
my @in2;
my @out;

my $swap = qx(vmstat);
$swap =~ s/\s+/ /g;
my @in1 = split / /, $swap;
#$swap = sprintf("%7s %7s %7s %7s", $in1[24], $in1[25], $in1[26], $in1[27]);

my $total = qx(free);
$total =~ s/\s+/ /g;
my @in2 = split / /, $total;
#$total = sprintf("%7s", $in2[15]);

push @out, " ";
push @out, sprintf("Total Swap:  %7s", $in2[15]);
push @out, " ";
push @out, "Swap in use:   swpd    free    buff   cache";
push @out, sprintf("            %7s %7s %7s %7s", $in1[25], $in1[26], $in1[27], $in1[28]);
push @out, " ";

close(CMD);

return (1, @out)

