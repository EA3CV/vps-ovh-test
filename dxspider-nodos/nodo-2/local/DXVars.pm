#
# The system variables - those indicated will need to be changed to suit your
# circumstances (and callsign)
#
# Copyright (c) 1998-2007 - Dirk Koopman G1TLH
#
#

package main;

# this really does need to change for your system!!!!
# use CAPITAL LETTERS
$mycall = "EA3CV-2";

# your name
$myname = "Kin";

# Your 'normal' callsign (in CAPTTAL LETTERS)
$myalias = "EA3CV";

# Your latitude (+)ve = North (-)ve = South in degrees and decimal degrees
$mylatitude = "+41.354167";

# Your Longtitude (+)ve = East, (-)ve = West in degrees and decimal degrees
$mylongitude = "+2.125000";

# Your locator (USE CAPITAL LETTERS)
$mylocator = "JN11BI";

# Your QTH (roughly)
$myqth = "Barcelona, Spain";

# Your e-mail address
$myemail = "ea3cv\@cronux.net";

# the country codes that my node is located in
#
# for example 'qw(EA EA8 EA9 EA0)' for Spain and all its islands.
# if you leave this blank then it will use the country code for
# your $mycall. This will suit 98% of sysops (including GB7 BTW).
#

@my_cc = qw();

# are we debugging ?
@debug = qw(chan connect cron msg progress state);

# are we doing xml?
$do_xml = 0;

# the SQL database DBI dsn
#$dsn = "dbi:SQLite:dbname=$root/data/dxspider.db";
#$dbuser = "";
#$dbpass = "";

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

1;
