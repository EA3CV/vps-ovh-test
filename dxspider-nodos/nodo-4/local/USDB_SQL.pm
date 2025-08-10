#
# Package to handle US Callsign -> City, State translations (SQL backend)
# Compatible con el backend original USDB.pm manteniendo estructura original
#

package USDB_SQL;

use strict;
use warnings;
use DBI;
use LWP::Simple;
use File::Temp qw(tempfile);
use IO::Uncompress::Gunzip qw(gunzip);
use DXVars;
use Encode;

my $table = 'usdb';
my $dbh;

sub init {
	my ($dsn, $user, $pass);

	if ($main::db_backend eq 'sqlite') {
		$dsn  = $main::sqlite_dsn;
		$user = $main::sqlite_dbuser;
		$pass = $main::sqlite_dbpass;
		$dbh = DBI->connect($dsn, $user, $pass, {
			RaiseError => 1,
			AutoCommit => 1,
			sqlite_unicode => 1,
		}) or die "[USDB_SQL] SQLite connect error: $DBI::errstr";
	} else {
		$dsn  = "DBI:mysql:database=$main::mysql_db;host=$main::mysql_host";
		$user = $main::mysql_user;
		$pass = $main::mysql_pass;
		$dbh = DBI->connect($dsn, $user, $pass, {
			RaiseError => 1,
			AutoCommit => 1,
			mysql_enable_utf8mb4 => 1,
		}) or die "[USDB_SQL] MySQL connect error: $DBI::errstr";
	}

	unless (_table_exists()) {
		print "[USDB_SQL] Table usdb not found. Creating...\n";
		_create_table();
		print "[USDB_SQL] Table 'usdb' created (empty)\n";
	}

	$USDB::present = 1; # necesario para que sh/usdb no devuelva 'db3'
	return "[USDB_SQL] Table 'usdb' ready";
}

sub load {
	my $class = shift;

	my $url        = 'ftp://ftp.w1nr.net/usdbraw.gz';
	my $local_data = $main::local_data || "$main::root/local_data";
	my $gzfile     = "$local_data/usdbraw.gz";
	my $txtfile    = "$local_data/usdbraw.txt";

	print "[USDB_SQL] Downloading from $url to $gzfile...\n";
	my $res = getstore($url, $gzfile);
	unless (is_success($res)) {
		warn "[USDB_SQL] Download failed: HTTP status $res\n";
		return "[USDB_SQL] Table unchanged: download failed";
	}

	print "[USDB_SQL] Decompressing $gzfile to $txtfile...\n";
	my $ok = IO::Uncompress::Gunzip::gunzip(
		$gzfile => $txtfile,
		MultiStream => 1,
		Append      => 0,
	);

	unless ($ok) {
		warn "[USDB_SQL] Gunzip failed for $gzfile\n";
		return "[USDB_SQL] Table unchanged: decompression failed";
	}

	open my $fh, '<:utf8', $txtfile or do {
		warn "[USDB_SQL] Cannot open $txtfile: $!\n";
		return "[USDB_SQL] Table unchanged: cannot read $txtfile";
	};

	unless (_table_exists()) {
		print "[USDB_SQL] Table usdb not found. Creating...\n";
		_create_table();
	}

	print "[USDB_SQL] Loading data into usdb table...\n";

	$dbh->do("ALTER TABLE usdb DISABLE KEYS") if $main::db_backend eq 'mysql';
	$dbh->begin_work if $main::db_backend eq 'sqlite';

	my @batch;
	my $batch_size = 1000;

	my $insert_prefix = $main::db_backend eq 'sqlite'
		? "INSERT OR IGNORE INTO `usdb` (`call`, `city`, `state`) VALUES "
		: "INSERT IGNORE INTO `usdb` (`call`, `city`, `state`) VALUES ";

	while (<$fh>) {
		chomp;
		next unless /^\s*([A-Z0-9]+)\|([^|]+)\|([A-Z]{2})\s*$/i;
		my ($call, $city, $state) = (uc($1), ucfirst(lc($2)), uc($3));
		my $quoted_city = $dbh->quote($city);
		push @batch, "('$call', $quoted_city, '$state')";

		if (@batch >= $batch_size) {
			my $sql = $insert_prefix . join(", ", @batch);
			$dbh->do($sql);
			@batch = ();
		}
	}

	if (@batch) {
		my $sql = $insert_prefix . join(", ", @batch);
		$dbh->do($sql);
	}

	close $fh;

	$dbh->commit if $main::db_backend eq 'sqlite';
	$dbh->do("ALTER TABLE usdb ENABLE KEYS") if $main::db_backend eq 'mysql';

	my ($total) = $dbh->selectrow_array("SELECT COUNT(*) FROM usdb");
	return "[USDB_SQL] Table now contains $total records";
}

sub get {
    my ($call) = @_;
    $call = uc($call);
    print "[USDB_SQL::get] CALLED with: $call\n";

    return unless $dbh;
    $call = uc($call);

    my $sth = $dbh->prepare("SELECT city, state FROM `$table` WHERE `call` = ?");
    $sth->execute($call);
    my ($city, $state) = $sth->fetchrow_array;

    if (defined $city && defined $state) {
        print "[USDB_SQL::get] FOUND: $call -> $city, $state\n";
        return ($city, $state);
    } else {
        print "[USDB_SQL::get] NOT FOUND: $call\n";
        return;
    }
}

sub getcity {
	my ($call) = @_;
	my ($city, undef) = get($call);
	return $city;
}

sub getstate {
	my ($call) = @_;
	my (undef, $state) = get($call);
	return $state;
}

sub _table_exists {
	if ($main::db_backend eq 'sqlite') {
		my $sth = $dbh->prepare("SELECT name FROM sqlite_master WHERE type='table' AND name=?");
		$sth->execute($table);
		my ($exists) = $sth->fetchrow_array;
		return defined $exists;
	} else {
		my $sth = $dbh->prepare("SHOW TABLES LIKE ?");
		$sth->execute($table);
		my ($exists) = $sth->fetchrow_array;
		return defined $exists;
	}
}

sub _create_table {
	my $sql;

	if ($main::db_backend eq 'mysql') {
		$sql = qq{
CREATE TABLE IF NOT EXISTS usdb (
  `call`  VARCHAR(16) NOT NULL,
  city    VARCHAR(64) DEFAULT NULL,
  state   CHAR(2)     DEFAULT NULL,
  PRIMARY KEY (`call`)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
		};
	} else {
		$sql = qq{
CREATE TABLE IF NOT EXISTS usdb (
  call  TEXT PRIMARY KEY,
  city  TEXT,
  state TEXT
);
		};
	}

	$dbh->do($sql);
	print "[USDB_SQL] Table usdb created\n";
}

1;
