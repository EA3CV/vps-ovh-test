#
# DXPredict.pm - Módulo para consultar score de QSO usando el contenedor predictor
#

package DXPredict;

use strict;
use warnings;
use JSON;
use Mojo::UserAgent;
use DateTime;
use DXUtil;
use USDB;
use Prefix;
use DXDebug;

our $predict_url = "http://localhost:5000/predict";
my %prediction_cache;

sub get_score {
    my %args = @_;

    # Validación de argumentos requeridos
    unless ($args{tx_call} && $args{rx_call} && $args{freq} && $args{mode}) {
        warn "[DXPredict] Missing required arguments to get_score";
        return undef;
    }

    my $tx_call = uc($args{tx_call});
    my $rx_call = uc($args{rx_call});
    my $freq    = $args{freq};
    my $mode    = uc($args{mode});

    my $cache_key = join(":", $tx_call, $rx_call, $freq, $mode);

    if (exists $prediction_cache{$cache_key}) {
        dbg("[DXPredict] Using cached prediction for $cache_key") if isdbg('predict');
        return $prediction_cache{$cache_key};
    }

    my ($tx_lat, $tx_lon) = _get_coords($tx_call);
    unless (defined $tx_lat && defined $tx_lon) {
        dbg("[DXPredict] No se encontraron coordenadas para $tx_call");
    }

    my ($rx_lat, $rx_lon) = _get_coords($rx_call);
    unless (defined $rx_lat && defined $rx_lon) {
        dbg("[DXPredict] No se encontraron coordenadas para $rx_call");
    }

    dbg("[DXPredict] Coordinates tx=($tx_lat,$tx_lon) rx=($rx_lat,$rx_lon)") if isdbg('predict');

    unless (defined $tx_lat && defined $tx_lon && defined $rx_lat && $rx_lon) {
        dbg("[DXPredict] Missing coordinates: tx=($tx_lat,$tx_lon) rx=($rx_lat,$rx_lon)");
        return undef;
    }

    dbg("[DXPredict] Llamando a API con tx=($tx_lat,$tx_lon) rx=($rx_lat,$rx_lon), freq=$freq, mode=$mode") if isdbg('predict');

    my $datetime_utc = DateTime->now(time_zone => 'UTC')->iso8601() . 'Z';

    my $ua = Mojo::UserAgent->new;
    my $res = $ua->post($predict_url => json => {
        tx_call      => $tx_call,
        rx_call      => $rx_call,
        tx_lat       => $tx_lat,
        tx_lon       => $tx_lon,
        rx_lat       => $rx_lat,
        rx_lon       => $rx_lon,
        freq_mhz     => $freq,
        mode         => $mode,
        datetime_utc => $datetime_utc,
    })->result;

    unless ($res->is_success) {
        dbg("[DXPredict] API error: " . $res->message);
        return undef;
    }

    my $j = $res->json;

    my $score             = $j->{score};
    my $proppy_score      = $j->{proppy_score};
    my $greyline_bonus    = $j->{greyline_bonus};
    my $rbn_density_score = $j->{rbn_density_score};
    my $psk_heard         = $j->{psk_heard};
    my $snr               = $j->{details}->{snr};
    my $rel               = $j->{details}->{rel};
    my $tx_greyline       = $j->{details}->{greyline}->{tx};
    my $rx_greyline       = $j->{details}->{greyline}->{rx};

    $prediction_cache{$cache_key} = {
        score             => $score,
        proppy_score      => $proppy_score,
        greyline_bonus    => $greyline_bonus,
        rbn_density_score => $rbn_density_score,
        psk_heard         => $psk_heard,
        details => {
            snr => $snr,
            rel => $rel,
            greyline => {
                tx => $tx_greyline,
                rx => $rx_greyline,
            }
        }
    };

    dbg("[DXPredict] Caching prediction for $cache_key") if isdbg('predict');
    return $prediction_cache{$cache_key};
}

sub _get_coords {
    my ($call) = @_;
    return unless $call;

    my ($city, $state_abbr) = USDB_SQL::get($call);
    my $state = _state_fullname($state_abbr) if $state_abbr;

    dbg("[DXPredict] USDB_SQL para $call -> city='$city', state_abbr='$state_abbr', state='$state'") if isdbg('predict');

    my @list = Prefix::extract($call);
    dbg("[DXPredict] Prefix::extract devolvió " . scalar(@list) . " entradas para $call") if isdbg('predict');

    if ($city) {
        foreach my $obj (@list) {
            next unless ref($obj);
            my $name = $obj->name || '';
            dbg("[DXPredict] Comparando city='$city' con name='$name'") if isdbg('predict');
            if ($name =~ /\b\Q$city\E\b/i) {
                dbg("[DXPredict] Coincidencia exacta con ciudad: $name") if isdbg('predict');
                return ($obj->lat, $obj->long);
            }
        }
        dbg("[DXPredict] Ninguna coincidencia con city '$city'") if isdbg('predict');
    }

    if ($state) {
        foreach my $obj (@list) {
            next unless ref($obj);
            my $name = $obj->name || '';
            dbg("[DXPredict] Comparando state='$state' con name='$name'") if isdbg('predict');
            if ($name =~ /\b\Q$state\E\b/i || $name =~ /\b\Q$state\E[-\w]*/i) {
                dbg("[DXPredict] Coincidencia con estado: $name") if isdbg('predict');
                return ($obj->lat, $obj->long);
            }
        }
        dbg("[DXPredict] Ninguna coincidencia con estado '$state'") if isdbg('predict');
    }

    foreach my $obj (@list) {
        if (ref($obj)) {
            dbg("[DXPredict] Explorando fallback: name='" . ($obj->name // '') . "', lat=" . ($obj->lat // '?') . ", long=" . ($obj->long // '?')) if isdbg('predict');
            if (defined $obj->lat && defined $obj->long) {
                dbg("[DXPredict] Usando fallback de coordenadas") if isdbg('predict');
                return ($obj->lat, $obj->long);
            }
        }
    }

    dbg("[DXPredict] No se encontraron coordenadas para $call");
    return;
}

sub _state_fullname {
    my $abbr = uc shift;
    my %states = (
        AL => 'Alabama', AK => 'Alaska', AZ => 'Arizona', AR => 'Arkansas',
        CA => 'California', CO => 'Colorado', CT => 'Connecticut', DE => 'Delaware',
        FL => 'Florida', GA => 'Georgia', HI => 'Hawaii', ID => 'Idaho',
        IL => 'Illinois', IN => 'Indiana', IA => 'Iowa', KS => 'Kansas',
        KY => 'Kentucky', LA => 'Louisiana', ME => 'Maine', MD => 'Maryland',
        MA => 'Massachusetts', MI => 'Michigan', MN => 'Minnesota', MS => 'Mississippi',
        MO => 'Missouri', MT => 'Montana', NE => 'Nebraska', NV => 'Nevada',
        NH => 'New-Hampshire', NJ => 'New-Jersey', NM => 'New-Mexico', NY => 'New-York',
        NC => 'North-Carolina', ND => 'North-Dakota', OH => 'Ohio', OK => 'Oklahoma',
        OR => 'Oregon', PA => 'Pennsylvania', RI => 'Rhode-Island', SC => 'South-Carolina',
        SD => 'South-Dakota', TN => 'Tennessee', TX => 'Texas', UT => 'Utah',
        VT => 'Vermont', VA => 'Virginia', WA => 'Washington', WV => 'West-Virginia',
        WI => 'Wisconsin', WY => 'Wyoming', DC => 'District-of-Columbia'
    );
    return $states{$abbr} || $abbr;
}

#
# Comando: sh/predict <tx_call> <rx_call> <freq> <mode>
#

package DXPredict::Cmd;

sub main {
    my ($self, $line) = @_;
    my ($tx, $rx, $freq, $mode) = split(/\s+/, $line);

    return (1, "Usage: sh/predict <spotter> <dx> <freq> <mode>")
        unless $tx && $rx && $freq && $mode;

    my $score = DXPredict::get_score({
        tx_call => $tx,
        rx_call => $rx,
        freq    => $freq,
        mode    => $mode
    });

    return (1, "Prediction not available") unless $score;

    return (1, sprintf <<'END', $tx, $rx, $freq, $mode,
Prediction score for %s  . %s on %s %s:
  Score...............: %d
  Proppy (rel=%.1f)..: %d
  SNR.................: %.1f dB
  Greyline bonus......: +%d (TX: %s, RX: %s)
  RBN density bonus...: +%d
  PSKReporter heard...: %s
END
        $score->{score},
        $score->{details}->{rel},
        $score->{proppy_score},
        $score->{details}->{snr},
        $score->{greyline_bonus},
        $score->{details}->{greyline}->{tx} ? "yes" : "no",
        $score->{details}->{greyline}->{rx} ? "yes" : "no",
        $score->{rbn_density_score},
        $score->{psk_heard} ? "yes" : "no"
    );
}

1;
