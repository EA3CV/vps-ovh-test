#!/usr/bin/perl

# List daily connections
# Put in sysop user's crontab
#
# Usage: ./make_list_conn.pl
#
# Created by EA3CV
#
# 20200615 v2.4
#
 
use strict;
use 5.010;
use Time::Piece;
use Time::Seconds;
use Data::Dumper;
use Date::Manip;
use warnings;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

$year += 1900;
$mon++;

my $y = $year;
my $d = sprintf("%03s", $yday);

my $time = Time::Piece->new;
$time  = $time - ONE_DAY;
my $fecha = $time->ymd("");

my $log_dat = "/spider/local_data/debug/$y/$d.dat";

open INPUT, '<', $log_dat || die "Can not open input file: $!\n";

my $line;
my @rray;
my @conn;

while($line = <INPUT>){
   chomp($line);

   my @line = split(m[(?:\^| )+], $line);

   my $Date  = $line[0];
   my $dxc   = $line[2];
   my $call  = $line[3];
   my $state = $line[4];

   my $date = localtime($Date)->strftime('%F %T');

   if ($dxc eq "DXChannel") {
      my $newline = "$date $dxc $call $state";
      push @rray, $newline;
#      say "$newline";
   }
}
close INPUT;

open(LOG,">/spider/local_data/debug/list_conn_$fecha.txt");

say LOG " ";
say LOG "Date        Conn      Disc      Call       Time";
say LOG "----------  --------  --------  ---------  -----------";

foreach ( @rray ) {
   chomp (@rray);
   push @conn, [ split / / ];
}

@conn = sort {$a->[3] cmp $b->[3]} @conn;

my $m;
my @sum = (['Call', 'H', 'M']);

foreach my $i (0 .. $#conn) { 
   if ($conn[$i][4] eq "created") {
      my ($Date_i, $Time_i, $Call, $state) = ($conn[$i][0], $conn[$i][1], $conn[$i][3], $conn[$i][4]);
      $m = $i;
      foreach $m ($m .. $#conn) {
         if ($conn[$m][3] eq $Call && $conn[$m][4] eq "destroyed") {
            my $Time_f = $conn[$m][1];
            my $Date_f = $conn[$m][0];
            my @tiempo = delta($Date_i, $Time_i, $Date_f, $Time_f);
            sum($conn[$i][3], $tiempo[0], $tiempo[1]);
            say LOG sprintf ("%-10s  %-8s  %-8s  %-9s %4s h  %2s m", $Date_i, $Time_i, $Time_f, $Call, $tiempo[0], $tiempo[1]);
            $conn[$m][4] = " ";
            last;
         } elsif ($m == $#conn) {
             my $Time_i = $conn[$i][1];
             my $Date_i = $conn[$i][0];
             my $Time_f = "23:59:59";
             my $Date_f = $conn[$i][0];
             my @tiempo = delta($Date_i, $Time_i, $Date_f, $Time_f);
             sum($conn[$i][3], $tiempo[0], $tiempo[1]);
             say LOG sprintf ("%-10s  %-8s            %-9s >%3s h  %2s m", $conn[$i][0], $conn[$i][1], $conn[$i][3], $tiempo[0], $tiempo[1]);
         }
      }
   } elsif ($conn[$i][4] eq "destroyed") {
        my $Time_i = "00:00:00";
        my $Date_i = $conn[$i][0];
        my $Time_f = $conn[$i][1];
        my $Date_f = $conn[$i][0];
        my @tiempo = delta($Date_i, $Time_i, $Date_f, $Time_f);
        sum($conn[$i][3], $tiempo[0], $tiempo[1]);
        say LOG sprintf ("%-10s            %-8s  %-9s >%3s h  %2s m", $conn[$i][0], $conn[$i][1], $conn[$i][3], $tiempo[0], $tiempo[1]);
        $i++;
   }
}
say LOG " ";
say LOG "Total usage time";
say LOG "---------------------- ";

#@sum = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @sum;

foreach my $i (1 .. $#sum) {
   say LOG sprintf ("%-9s %4s h %3s m", $sum[$i][0], $sum[$i][1], $sum[$i][2]);
}
say LOG " ";

close LOG;

sub delta {
        my ($date1, $time1 ,$date2, $time2) = @_;

        $date1 = $date1." ".$time1;
        $date2 = $date2." ".$time2;
        $date1 = ParseDate($date1);
        $date2 = ParseDate($date2);

        my $date_diff = DateCalc($date1,$date2);
        my @diff = split(":",$date_diff);

        return $diff[4], $diff[5];
}

sub sum {
        my ($call, $h ,$m) = @_;
	foreach my $k (0 .. $#sum) {
           if ($sum[$k][0] eq $call) {
              my $min = $sum[$k][2] + $m;
              if ($min > 59){
                 my $hour = int($min / 60);
                 $min -= ($hour * 60);
                 $sum[$k][1] = $sum[$k][1] + $h + $hour;
              } else {
                   $sum[$k][1] = $sum[$k][1] + $h;
              }
              $sum[$k][2] = $min;
              last;
           } elsif ($k == $#sum) {
                my $new = "$call,$h,$m";
                push @sum, [@_];
           }
	}
}
