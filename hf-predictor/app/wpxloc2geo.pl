#!/usr/bin/perl

# cty2geo_full_prefix_2dec.pl - extrae todos los prefijos (excluyendo '/'), redondeando coordenadas a 2 decimales

# Kin 20250807 v1.o

use strict;
use warnings;

my %cty;
while (<>) {
    chomp;
    # saltar encabezados y comentarios
    next if /^\s*!/;
    # saltar líneas vacías
    next if /^\s*$/;

    # separar tokens
    my @f = split;
    # el primer token contiene uno o varios prefijos separados por comas
    my $pref_field = shift @f;

    # obtener los últimos 8 tokens que corresponden a lat/lon
    next unless @f >= 8;
    my ($gd, $gm, $gs, $dir_lat, $ld, $lm, $ls, $dir_lon) = @f[-8..-1];

    # convertir a decimal
    my $lat = $gd + $gm/60 + $gs/3600;
    $lat = -$lat if $dir_lat eq 'S';
    my $lon = $ld + $lm/60 + $ls/3600;
    $lon = -$lon if $dir_lon eq 'W';

    # formatear con 2 decimales
    my $latf = sprintf("%.2f", $lat);
    my $lonf = sprintf("%.2f", $lon);

    # procesar cada prefijo individual
    for my $pref (split /,/, $pref_field) {
        next unless $pref;
        next if $pref =~ m{/};
        # almacenar o sobrescribir con las coordenadas
        $cty{$pref} = [$latf, $lonf];
    }
}

# impresión JSON, un prefijo por línea
my @keys = sort keys %cty;
print "{\n";
for my $i (0..$#keys) {
    my $p = $keys[$i];
    my ($la, $lo) = @{ $cty{$p} };
    my $comma = $i == $#keys ? "" : ",";
    printf qq(  "%s" : ["%s", "%s"]%s\n), $p, $la, $lo, $comma;
}
print "}\n";
