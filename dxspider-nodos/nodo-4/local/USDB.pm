#
# Package to handle US Callsign -> City, State translations
#
# Copyright (c) 2002 Dirk Koopman G1TLH
#

package USDB;

use strict;

use DXVars;
use SysVar;
use DB_File;
use File::Copy;
use DXDebug;
use DXUtil;

#use Compress::Zlib;

use vars qw(%db $present $dbfn);

BEGIN {
    if ($main::db_backend && $main::db_backend =~ /^(mysql|sqlite)$/i) {
        eval {
            require USDB_SQL;
            *init      = \&USDB_SQL::init;
            *end       = \&USDB_SQL::end;
            *get       = \&USDB_SQL::get;
            *add       = \&USDB_SQL::add;
            *del       = \&USDB_SQL::del;
            *getstate  = \&USDB_SQL::getstate;
            *getcity   = \&USDB_SQL::getcity;
            *load      = \&USDB_SQL::load;
        };
        warn "[USDB] Error loading SQL backend: $@" if $@;
    }
}

localdata_mv("usdb.v1");
$dbfn = localdata("usdb.v1");

sub init
{
    # Si el backend es SQL, delegamos a USDB_SQL
    if ($main::db_backend && $main::db_backend =~ /^(mysql|sqlite)$/i) {
        eval {
            require USDB_SQL;
            USDB_SQL->import();
        };
        if ($@) {
            return "[USDB] Error loading USDB_SQL.pm: $@";
        }
        $USDB::present = 1;
        return USDB_SQL::init();
    }

    # Backend original: fichero usdb.v1
    end();
    if (tie %db, 'DB_File', $dbfn, O_RDWR, 0664, $DB_BTREE) {
        $present = 1;
        return "US Database loaded";
    }
    return "US Database not loaded";
}

sub end
{
    return unless $present;
    untie %db;
    undef $present;
}

unless ($main::db_backend && $main::db_backend =~ /^(mysql|sqlite)$/i) {

    sub get {
        my ($call) = @_;

        if ($main::db_backend && $main::db_backend =~ /^(mysql|sqlite)$/i) {
            require USDB_SQL;
            return USDB_SQL::get($call);
        }

        return () unless $present;
        my $ctyn = $db{$call};
        my @s = split /\|/, $db{$ctyn} if $ctyn;
        return @s;
    }

    sub getstate
    {
        return () unless $present;
        my @s = get($_[0]);
        return @s ? $s[1] : undef;
    }

    sub getcity
    {
        return () unless $present;
        my @s = get($_[0]);
        return @s ? $s[0] : undef;
    }
}

sub _add
{
    my ($db, $call, $city, $state) = @_;

    # lookup the city 
    my $s = uc "$city|$state";
    my $ctyn = $db->{$s};
    unless ($ctyn) {
        my $no = $db->{'##'} || 1;
        $ctyn = "#$no";
        $db->{$s} = $ctyn;
        $db->{$ctyn} = $s; 
        $no++;
        $db->{'##'} = "$no";
    }
    $db->{uc $call} = $ctyn; 
}

sub add
{
    _add(\%db, @_);
}

sub del
{
    my $call = uc shift;
    delete $db{$call};
}

#
# load in / update an existing DB with a standard format (GZIPPED)
# "raw" file.
#
# Note that this removes and overwrites the existing DB file
# You will need to init again after doing this
# 

sub load
{
    # If using SQL backend, delegate to USDB_SQL
    if ($main::db_backend && $main::db_backend =~ /^(mysql|sqlite)$/i) {
        eval {
            require USDB_SQL;
            USDB_SQL->import();
        };
        if ($@) {
            return "[USDB] Error loading USDB_SQL.pm: $@";
        }
        return USDB_SQL::load();
    }

    return "Need a filename" unless @_;

    # create the new output file
    my $a = new DB_File::BTREEINFO;
    $a->{psize} = 4096 * 2;
    my $s = 0;

    # guess a cache size
    for (@_) {
        my $ts = -s;
        $s = $ts if $s > $ts;
    }
    if ($s > 1024 * 1024) {
        $a->{cachesize} = int($s / (1024*1024)) * 3 * 1024 * 1024;
    }

#   print "cache size " . $a->{cachesize} . "\n";

    my %dbn;
    if (-e $dbfn ) {
        copy($dbfn, "$dbfn.old") or return "cannot copy $dbfn -> $dbfn.old $!";
    }

    unlink "$dbfn.new";
    tie %dbn, 'DB_File', "$dbfn.new", O_RDWR|O_CREAT, 0664, $a or return "cannot tie $dbfn.new $!";

    # now write away all the files
    my $count = 0;
    for (@_) {
        my $ofn = shift;

        return "Cannot find $ofn" unless -r $ofn;

        my $nfn = $ofn;
        if ($nfn =~ /.gz$/i) {
            my $gz;
            eval qq{use Compress::Zlib; \$gz = gzopen(\$ofn, "rb")};
            return "Cannot read compressed files $@ $!" if $@ || !$gz;
            $nfn =~ s/.gz$//i;
            my $of = new IO::File ">$nfn" or return "Cannot write to $nfn $!";
            my ($l, $buf);
            $of->write($buf, $l) while ($l = $gz->gzread($buf));
            $gz->gzclose;
            $of->close;
            $ofn = $nfn;
        }

        my $of = new IO::File "$ofn" or return "Cannot read $ofn $!";

        while (<$of>) {
            my $l = $_;
            $l =~ s/[\r\n]+$//;
            my ($call, $city, $state) = split /\|/, $l;

            _add(\%dbn, $call, $city, $state);

            $count++;
        }
        $of->close;
        unlink $nfn;
    }

    untie %dbn;
    rename "$dbfn.new", $dbfn;
    return "$count records";
}

1;
