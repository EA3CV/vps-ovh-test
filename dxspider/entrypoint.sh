#!/usr/bin/env bash

#
# by Kin EA3CV
#
# DXSpider entrypoint
#

set -euo pipefail

mkdir -p /spider/cmd_import
rm -f /spider/local_data/cluster.lck || true

cd /spider/perl
./update_sysop.pl

exec ./cluster.pl


