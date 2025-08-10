#
# show/predict
#
# Usage: sh/predict <spotter> <dx> <freq> <mode>
#
# Copyright (c) 2025 Kin EA3CV
#

my ($self, $line) = @_;

my @args = split ' ', $line;

unless (@args == 4) {
    return (1, "Usage: sh/predict <spotter> <dx> <freq> <mode>");
}

my ($tx, $rx, $freq, $mode) = @args;

require DXPredict;

my $result = DXPredict::get_score(
    tx_call => $tx,
    rx_call => $rx,
    freq    => $freq,
    mode    => $mode,
);

unless ($result && defined $result->{score}) {
    return (1, "Prediction not available");
}

my @out;
push @out, "Prediction score for $tx → $rx on $freq $mode:";
push @out, "";
push @out, sprintf("  Score...............: %d", $result->{score});
push @out, sprintf("  Proppy (rel=%.1f)...: %d", $result->{details}->{rel}, $result->{proppy_score});
push @out, sprintf("  SNR.................: %.1f dB", $result->{details}->{snr});
push @out, sprintf("  Greyline bonus......: +%d (TX: %s, RX: %s)",
    $result->{greyline_bonus},
    $result->{details}->{greyline}->{tx} ? 'yes' : 'no',
    $result->{details}->{greyline}->{rx} ? 'yes' : 'no'
);
push @out, sprintf("  RBN density bonus...: +%d", $result->{rbn_density_score});
push @out, sprintf("  PSKReporter heard...: %s", $result->{psk_heard} ? "yes" : "no");

return (1, @out);
