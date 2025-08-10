#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use JSON;

my $dbh = DBI->connect("dbi:SQLite:dbname=/home/sysop/spider/local_data/dxspider.sqlite", "", "", {
    RaiseError => 1,
    AutoCommit => 1,
});

my $json = JSON->new;

my $sth = $dbh->prepare("SELECT call, \"group\", buddies FROM users");
$sth->execute();

while (my $row = $sth->fetchrow_hashref) {
    foreach my $field (qw(group buddies)) {
        next unless defined $row->{$field};
        eval { $json->decode($row->{$field}) };
my $g = defined($row->{group}) ? $row->{group} : '';
my $b = defined($row->{buddies}) ? $row->{buddies} : '';
print "[$row->{call}] group: $g | buddies: $b\n";

        if ($@) {
            print "MALFORMED: $row->{call} field '$field': $row->{$field}\n";
        }
    }
}
