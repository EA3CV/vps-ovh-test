#
#   Modify by Kin EA3CV
#
#   Docker personalizado para la versión 1.57 (rama mojo) y para EA4URE-2
#
#   Adapted for DXSpider 1.57 installation
#   20230201  v1.6
#

FROM alpine:3.16

ENV SPIDER_USERNAME=${SPIDER_USERNAME:-sysop} SPIDER_UID=${SPIDER_UID:-1000}

COPY entrypoint.sh /entrypoint.sh

RUN apk update && \
    apk add --update --no-cache git musl-dev \
        gcc make \
        ncurses-libs ncurses-dev \
        perl-db_file perl-dev perl-digest-sha1 perl-io-socket-ssl \
        perl-net-telnet perl-timedate perl-yaml-libyaml \
        perl-test-simple perl-app-cpanminus \
        perl-json-maybexs-1.004002-r0 \
        perl-netaddr-ip \
        wget curl perl bash nano \
        tini tg && \
    cpanm --no-wget Curses Date::Manip && \
    cpanm EV Mojolicious JSON JSON::XS Data::Structure::Util && \
    cpanm Math::Round List::MoreUtils Date::Calc && \
    cpanm Net::MQTT::Simple && \
    cpanm Net::CIDR::Lite && \
    cpanm File::Copy::Recursive && \
    adduser -D -u $SPIDER_UID -h /spider $SPIDER_USERNAME && \
    git clone git://scm.dxcluster.org/scm/spider -b mojo /spider &&  \
    cd /spider && \

    git reset --hard && \
    git pull && \

    (cd /spider/src && make) && \

    apk del --purge gcc make musl-dev ncurses-dev perl-app-cpanminus perl-dev && \
    rm -rf /var/cache/apk/* && \
    rm -rf /resources  

ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]