#
# reload the usdb file
#
# Be warned, if this is the full database the size of your image will
# increase by at least 20Mb and all activity will stop for several
# minutes
# 
# So there.
#
# Copyright (c) 2002 Dirk Koopman G1TLH
#
#
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) if $self->priv < 9;

my ($cmd, $file) = split(/\s+/, $line, 2);

if ($main::db_backend && $main::db_backend =~ /^(mysql|sqlite)$/i) {
    return (1, USDB::load());
}

# FILE backend
return (1, USDB::init());
