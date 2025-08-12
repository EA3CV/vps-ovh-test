#!/usr/bin/env perl

#
#  descarga_spacewx.pl — Descarga índices solares y publica en Redis (y/o fichero)
#
#  Datos: F107 (diario observado), Ap (diario), Kp (último 3h)
#  Salida JSON: {fetched_utc, f107, ap, kp, kp_time}
#
#  Uso:
#    perl descarga_spacewx.pl [--cache spacewx_cache.json] [--redis]
#                             [--redis-host redis] [--redis-port 6379]
#                             [--redis-key spacewx:latest] [--expire 21600]
#                             [--print-in] [--timeout 15]
#
#  Requisitos:
#    - Perl 5.x, JSON::PP, HTTP::Tiny
#    - (opcional) Redis.pm; si no, fallback a `redis-cli`
#
#  Author  : Kin EA3CV <ea3cv@cronux.net>
#  Version : 20250809 v1.0
#

use strict;
use warnings;
use JSON::PP qw(decode_json encode_json);
use HTTP::Tiny;
use Getopt::Long;
use Time::Piece;

# --- Endpoints NOAA/SWPC ---
my %URL = (
  f107_txt => 'https://services.swpc.noaa.gov/text/daily-solar-indices.txt',
  ap_txt   => 'https://services.swpc.noaa.gov/text/daily-geomagnetic-indices.txt',
  kp_json  => 'https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json',
);

# --- CLI options ---
my $cache_file = 'spacewx_cache.json';
my $print_in   = 0;
my $timeout_s  = 15;

# Redis options
my $use_redis  = 0;
my $redis_host = 'redis';
my $redis_port = 6379;
my $redis_key  = 'spacewx:latest';
my $redis_exp  = 6 * 3600;   # 6h, en línea con max_age_hours=6
GetOptions(
  'cache=s'     => \$cache_file,
  'print-in'    => \$print_in,
  'timeout=i'   => \$timeout_s,
  'redis!'      => \$use_redis,
  'redis-host=s'=> \$redis_host,
  'redis-port=i'=> \$redis_port,
  'redis-key=s' => \$redis_key,
  'expire=i'    => \$redis_exp,
) or die "Uso: $0 [--cache file.json] [--redis --redis-host redis --redis-port 6379 --redis-key spacewx:latest --expire 21600] [--print-in] [--timeout 15]\n";

my $ua = HTTP::Tiny->new(
  timeout => $timeout_s,
  agent   => "fetch_spacewx/1.1",
);

sub fetch_text {
  my ($url) = @_;
  my $res = $ua->get($url);
  die "HTTP error $res->{status} $res->{reason} for $url\n" unless $res->{success};
  return $res->{content};
}

sub fetch_json_array_last_kp {
  my ($url) = @_;
  my $res = $ua->get($url);
  return (undef, undef) unless $res->{success};
  my $data = eval { decode_json($res->{content}) };
  return (undef, undef) if $@ || ref($data) ne 'ARRAY' || !@$data;

  my $last;
  for my $row (reverse @$data) {
    if (ref($row) eq 'HASH' && exists $row->{kp_index}) {
      $last = $row; last;
    }
    if (ref($row) eq 'ARRAY' && @$row >= 2) {
      my $kp = $row->[1];
      if (defined $kp && $kp =~ /^-?\d+(\.\d+)?$/) {
        $last = { time_tag => $row->[0], kp_index => $kp }; last;
      }
    }
  }
  return (undef, undef) unless $last;
  my $kp  = $last->{kp_index} + 0;
  my $ts  = $last->{time_tag} // '';
  return ($kp, $ts);
}

sub parse_f107_from_txt {
  my ($txt) = @_;
  my @lines = grep { $_ !~ /^\s*#/ && $_ =~ /\d{4}\s+\d{2}\s+\d{2}/ } split /\R/, $txt;
  die "No F10.7 lines found\n" unless @lines;
  my $last = $lines[-1];
  my @f = split /\s+/, $last;
  die "Unexpected daily-solar-indices format\n" unless @f >= 4;
  my $f107 = $f[3];
  die "Bad F10.7 value\n" unless defined $f107 && $f107 =~ /^\d+$/;
  return $f107 + 0;
}

sub parse_ap_from_txt {
  my ($txt) = @_;
  my @lines = grep { $_ !~ /^\s*#/ && $_ =~ /^\s*\d{4}\s+\d{2}\s+\d{2}\s+/ } split /\R/, $txt;
  die "No Ap lines found\n" unless @lines;
  my $last = $lines[-1];

  $last =~ s/-/ /g;                    # normaliza "3-1-1"
  my @f = grep { length } split /\s+/, $last;

  die "Unexpected daily-geomagnetic-indices format\n" unless @f >= 30;

  my $Aplanet = $f[21];                # posición calculada (ver doc)
  die "Bad Ap value\n" unless defined $Aplanet && $Aplanet =~ /^-?\d+$/;

  return $Aplanet + 0;
}

# ---------- MAIN ----------
my %out = (
  fetched_utc => gmtime->datetime . "Z",
);

# F107
eval {
  my $txt = fetch_text($URL{f107_txt});
  $out{f107} = parse_f107_from_txt($txt);
  1;
} or do { warn "F107 fetch/parse failed: $@"; };

# Ap
eval {
  my $txt = fetch_text($URL{ap_txt});
  $out{ap} = parse_ap_from_txt($txt);
  1;
} or do { warn "Ap fetch/parse failed: $@"; };

# Kp (último tramo 3h)
eval {
  my ($kp, $ts) = fetch_json_array_last_kp($URL{kp_json});
  $out{kp}      = $kp if defined $kp;
  $out{kp_time} = $ts if defined $ts;
  1;
} or do { warn "Kp fetch/parse failed: $@"; };

# Guardar a fichero (si se pidió)
if (defined $cache_file && length $cache_file) {
  eval {
    open my $fh, '>', $cache_file or die "open $cache_file: $!";
    print {$fh} encode_json(\%out);
    close $fh;
    1;
  } or do { warn "Cache write failed: $@"; };
}

# Publicar en Redis (si se pidió)
if ($use_redis) {
  my $json = encode_json(\%out);

  my $published = 0;

  # 1) Intentar con el módulo Redis
  eval {
    require Redis;
    my $red = Redis->new( server => "$redis_host:$redis_port", reconnect => 2 );
    $red->set($redis_key, $json);
    $red->expire($redis_key, $redis_exp) if $redis_exp && $redis_exp > 0;
    $published = 1;
    1;
  } or do {
    warn "Perl Redis module not available or failed, will try redis-cli...\n";
  };

  # 2) Fallback: redis-cli
  if (!$published) {
    my $cmd_set = sprintf("redis-cli -h %s -p %d SET %s '%s'",
      $redis_host, $redis_port, $redis_key, _shell_escape_single($json)
    );
    my $rc1 = system($cmd_set);
    if ($rc1 == 0) {
      if ($redis_exp && $redis_exp > 0) {
        my $cmd_exp = sprintf("redis-cli -h %s -p %d EXPIRE %s %d",
          $redis_host, $redis_port, $redis_key, $redis_exp
        );
        my $rc2 = system($cmd_exp);
        warn "redis-cli EXPIRE failed ($rc2)" if $rc2 != 0;
      }
      $published = 1;
    } else {
      warn "redis-cli SET failed ($rc1)";
    }
  }

  warn "WARNING: Could not publish to Redis\n" unless $published;
}

# Snippet opcional para .in (solo informativo)
if ($print_in) {
  print "F107 $out{f107}\n" if defined $out{f107};
  print "Ap $out{ap}\n"     if defined $out{ap};
  print "Kp $out{kp}\n"     if defined $out{kp};
}

# Salida informativa a STDOUT
print encode_json(\%out), "\n";
exit 0;

# --- helpers ---
sub _shell_escape_single {
  my ($s) = @_;
  $s =~ s/'/'"'"'/g;  # escapado para single-quoted
  return $s;
}
