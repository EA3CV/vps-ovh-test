#!/usr/bin/env perl
use strict;
use warnings;
use Redis;
use JSON::PP;
use Getopt::Long;

# -----------------------------
# CLI / Config Redis
# -----------------------------
my $REDIS_HOST = $ENV{REDIS_HOST} // "localhost";
my $REDIS_PORT = $ENV{REDIS_PORT} // 6379;
my $DESC = 0;  # por defecto ascendente (último = más reciente)

GetOptions(
  "host=s" => \$REDIS_HOST,
  "port=i" => \$REDIS_PORT,
  "desc!"  => \$DESC,        # --desc => descendente (primero = más reciente)
) or die "Uso: $0 [--host redis] [--port 6379] [--desc]\n";

# -----------------------------
# Conexión a Redis
# -----------------------------
my $redis;
eval {
  $redis = Redis->new(
    server      => "$REDIS_HOST:$REDIS_PORT",
    reconnect   => 2,
    every       => 500_000,   # us
    cnx_timeout => 2,
    encoding    => undef,
  );
  1;
} or do {
  my $err = $@ || "error desconocido";
  die "No puedo conectar a Redis en $REDIS_HOST:$REDIS_PORT -> $err\n";
};

my $json = JSON::PP->new->utf8->canonical(1);

# -----------------------------
# Anchuras exactas (monospace)
# -----------------------------
my %W = (
    ts      => 25,  # izq
    source  => 6,   # izq
    spotter => 10,  # izq
    dx      => 10,  # izq
    freq    => 7,   # der (1 decimal)
    mode    => 7,   # izq
    sp_rel  => 4,   # der
    sp_snr  => 5,   # der
    lp_rel  => 4,   # der
    lp_snr  => 5,   # der
);

# -----------------------------
# Utilidades
# -----------------------------
sub pad_left  { my ($s, $w) = @_; $s = "" unless defined $s; return sprintf("%${w}s", $s); }
sub pad_right { my ($s, $w) = @_; $s = "" unless defined $s; $s =~ s/\s+/ /g; $s = substr($s,0,$w) if length($s) > $w; return sprintf("%-${w}s", $s); }
sub num_or_blank { defined $_[0] && $_[0] ne "" ? $_[0]+0 : "" }

sub fmt_freq {
    my ($f) = @_;
    return "" unless defined $f && $f ne "";
    return sprintf("%.1f", $f + 0);
}

sub mode_label {
    my ($m) = @_;
    return "-" unless defined $m && length $m;
    return "digital" if $m =~ /^(FT8|FT4|DIGI|DIGITAL|PSK|RTTY)$/i;
    return "cw"      if $m =~ /^CW$/i;
    return lc $m;
}

sub header_fixed {
    my $h1 =
        pad_right("timestamp",      $W{ts})     . "  " .
        pad_right("source",         $W{source}) . "  " .
        pad_right("spotter",        $W{spotter}). "  " .
        pad_right("dx",             $W{dx})     . "  " .
        pad_right("freq",           $W{freq})   . "  " .
        pad_right("mode",           $W{mode})   . "  " .
        pad_right("SP REL:SNR",     $W{sp_rel} + $W{sp_snr} + 1) . "  " .
        pad_right("LP REL:SNR",     $W{lp_rel} + $W{lp_snr} + 1) . "\n";

    my $h2 =
        ("-" x $W{ts})     . "  " .
        ("-" x $W{source}) . "  " .
        ("-" x $W{spotter}). "  " .
        ("-" x $W{dx})     . "  " .
        ("-" x $W{freq})   . "  " .
        ("-" x $W{mode})   . "  " .
        ("-" x ($W{sp_rel} + $W{sp_snr} + 1)) . "  " .
        ("-" x ($W{lp_rel} + $W{lp_snr} + 1)) . "\n";

    return $h1 . $h2;
}

sub line_fixed {
    my ($ts,$src,$spot,$dx,$freq,$mode,$sp_rel,$sp_snr,$lp_rel,$lp_snr) = @_;

    # Bloques SP/LP: EXACTAMENTE "%4s %5s" (REL=4 der, SNR=5 der, 1 espacio en medio)
    my $sp_txt = sprintf("%4s %5s",
        defined $sp_rel && $sp_rel ne "" ? $sp_rel : "",
        defined $sp_snr && $sp_snr ne "" ? $sp_snr : ""
    );
    my $lp_txt = sprintf("%4s %5s",
        defined $lp_rel && $lp_rel ne "" ? $lp_rel : "",
        defined $lp_snr && $lp_snr ne "" ? $lp_snr : ""
    );

    return join("  ",
        pad_right($ts,   $W{ts}),       # izq
        pad_right($src,  $W{source}),   # izq
        pad_right($spot, $W{spotter}),  # izq
        pad_right($dx,   $W{dx}),       # izq
        pad_left($freq,  $W{freq}),     # der
        pad_right($mode, $W{mode}),     # izq
        $sp_txt,                        # 10 chars exactos
        $lp_txt                         # 10 chars exactos
    ) . "\n";
}

# -----------------------------
# Cargar registros (human + rbn)
# -----------------------------
my @records;

for my $pattern ("spot:human:*", "spot:rbn:*") {
    my @keys = $redis->keys($pattern);
    for my $key (@keys) {
        my $val = $redis->get($key);
        next unless defined $val && length $val;

        my $obj;
        next unless eval { $obj = $json->decode($val); 1; };
        next unless ref($obj) eq 'HASH';

        my $ts   = $obj->{timestamp} // $obj->{ts} // "";
        my $src  = $obj->{source}    // "";
        my $spot = $obj->{spotter}   // "";
        my $dx   = $obj->{dx}        // "";

        my $freq_in = $obj->{frequency} // $obj->{freq};
        my $freq = fmt_freq($freq_in);

        my $mode = mode_label($obj->{mode});

        my ($sp_rel,$sp_snr,$lp_rel,$lp_snr) = ("","","","");
        if (ref($obj->{prediction}) eq 'HASH') {
            if (ref($obj->{prediction}{short_path}) eq 'HASH') {
                $sp_rel = num_or_blank($obj->{prediction}{short_path}{reliability});
                $sp_snr = num_or_blank($obj->{prediction}{short_path}{snr});
            }
            if (ref($obj->{prediction}{long_path}) eq 'HASH') {
                $lp_rel = num_or_blank($obj->{prediction}{long_path}{reliability});
                $lp_snr = num_or_blank($obj->{prediction}{long_path}{snr});
            }
        }

        push @records, {
            timestamp => $ts,
            source    => $src,
            spotter   => $spot,
            dx        => $dx,
            freq      => $freq,
            mode      => $mode,
            sp_rel    => $sp_rel,
            sp_snr    => $sp_snr,
            lp_rel    => $lp_rel,
            lp_snr    => $lp_snr,
        };
    }
}

# -----------------------------
# Orden por timestamp (ISO 8601)
# -----------------------------
@records = sort {
    my $A = $a->{timestamp} // "";
    my $B = $b->{timestamp} // "";
    $A =~ s/Z$/+00:00/;
    $B =~ s/Z$/+00:00/;
    $DESC ? ($B cmp $A) : ($A cmp $B)  # asc por defecto (último = más reciente)
} @records;

# -----------------------------
# Salida
# -----------------------------
print header_fixed();
for my $r (@records) {
    print line_fixed(
        $r->{timestamp},
        $r->{source},
        $r->{spotter},
        $r->{dx},
        $r->{freq},
        $r->{mode},
        $r->{sp_rel},
        $r->{sp_snr},
        $r->{lp_rel},
        $r->{lp_snr},
    );
}
