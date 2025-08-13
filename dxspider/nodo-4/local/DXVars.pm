# -*- perl -*-
# The system variables - those indicated will need to be changed to suit your
# circumstances (and callsign)
#
# Copyright (c) 1998-2007 - Dirk Koopman G1TLH
#
#

package main;

# List of nodes that make up the cluster
@cluster_nodes = qw(EA3CV-10 EA3CV-11 EA3CV-12);

# this really does need to change for your system!!!!			   
# use CAPITAL LETTERS
$mycall = "EA3CV-4";

# your name
$myname = "Kin";

# Your 'normal' callsign (in CAPTTAL LETTERS) 
$myalias = "EA3CV";

# Your latitude (+)ve = North (-)ve = South in degrees and decimal degrees
$mylatitude = +52.0;

# Your Longtitude (+)ve = East, (-)ve = West in degrees and decimal degrees
$mylongitude = +0.0;

# Your locator (USE CAPITAL LETTERS)
$mylocator = "JN11BI";

# Your QTH (roughly)
$myqth = "Hospitalet, Barcelona";

# Your e-mail address
$myemail = "ea3cv@cronux.net";

# the country codes that my node is located in
# 
# for example 'qw(EA EA8 EA9 EA0)' for Spain and all its islands.
# if you leave this blank then it will use the country code for
# your $mycall. This will suit 98% of sysops (including GB7 BTW).
#

@my_cc = qw();

# are we debugging ?
@debug = qw(chan state msg cron connect progress);

# are we doing xml?
$do_xml = 0;

$Internet::contest_host = "contest.dxtron.com";

# Telegram Bot
$id = "1089814914";
$token = "1376233105:AAHOfU_M97j1gXm1l4xLPpmF_v6CYCxIL3M";

# Email SMTP config
$email_enable = 1;
$email_from = 'ea3cv@cronux.net';
$email_smtp = 'smtp.migadu.com';
$email_port = 587;      # Port 587 for STARTTLS/Port 465 for SSL)
$email_user = 'ea3cv@cronux.net';
$email_pass = 'Gauss314.$';

# Backend selection
$db_backend = 'mysql'; # 'file', 'sqlite', 'mysql'

# Data for MySQL/MariaDB
$mysql_admin_user = "root";
$mysql_admin_pass = "rootpass";
$mysql_db   = "dxspider";
$mysql_user = "ea3cv";
$mysql_pass = "dxpass";
$mysql_host = "dx-mariadb";
#$mysql_table = "users";

# Data for SQLite
#$sqlite_dsn = "dbi:SQLite:dbname=$root/local_data/dxspider.db";
#$sqlite_dbuser = "";
#$sqlite_dbpass = "";

1;
