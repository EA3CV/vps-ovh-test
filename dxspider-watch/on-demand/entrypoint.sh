#!/bin/bash

#
# by Kin EA3CV
#
# DXSpider entrypoint
#

#mkdir /spider/cmd_import
rm /spider/local_data/cluster.lck
cd /spider/local_cmd
#./update_sysop.pl
./update_new_sysop.pl

cd /spider/perl
./cluster.pl &

