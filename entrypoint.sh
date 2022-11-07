#!/bin/bash

#
#   Modify by Kin EA3CV
#
#   Docker personalizado para la versión 1.57 (rama mojo) y para EA4URE-2
#
#   Adapted for DXSpider 1.57 installation
#   20200618  v1.5
#
#   Copyright 2018 Kristijan Conkas
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

#
# DXSpider entry point
#
#chmod -R 2775 /spider
#chmod -R 775 /spider/*.pl
#chown -R sysop:sysop /spider
mkdir /spider/cmd_import
rm /spider/local_data/cluster.lck
# A partir de la build 402
cd /spider/local_data
perl user_json
#
cd /spider/perl
./update_sysop.pl
./cluster.pl
