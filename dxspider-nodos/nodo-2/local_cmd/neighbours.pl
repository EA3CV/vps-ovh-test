#
# Usage: neignbours
#
# List of Node Status for bot Telegram
# also for console command
#
# Copyright 2020 Kin EA3CV
# Licensed under the Apache License, Version 2.0
#
# 20201016 v0.1a
#

use strict;
use 5.10.1;
use IO::File;

my $self = shift;
my $dxchan;
my @out;

open my $file, '<', '/spider/local_cmd/nodes.txt';
my %list_hash;
while (my $line = <$file>) {
    chomp $line;
    $line = uc($line);
    $list_hash{$line} = "DOWN";
}
close $file;

push @out, " ";
push @out, "   List of Node Status";
push @out, " ";

foreach $dxchan ( sort {$a->call cmp $b->call} DXChannel::get_all ) {
	my $call = $dxchan->call();
	my $type = $dxchan->is_node ? "NODE" : "USER";

        if ($type eq "NODE") {
		$list_hash{$call} = "UP";
	}
}

foreach my $key (sort (keys(%list_hash))) {
	push @out, sprintf("   %-10s     %-4s ", $key, $list_hash{$key});
}

my $uptime = main::uptime();

push @out, " ";
push @out, "   Uptime: $uptime";
push @out, " ";

my @status = join("\n",@out),"\n";

my $token = "1376233105:AAHOfU_M97j1gXm1l4xLPpmF_v6CYCxIL3M";
my $id = "1089814914";
my $url = "https://api.telegram.org/bot$token/sendMessage";
`curl -s -X POST $url -d chat_id=$id -d text='@status'`;

return (1, @out)
