FROM alpine:3.21

ARG SPIDER_USERNAME=sysop
ARG SPIDER_UID=1000

ENV SPIDER_USERNAME=$SPIDER_USERNAME
ENV SPIDER_UID=$SPIDER_UID

ENV LANG=es_ES.UTF-8
ENV LC_ALL=es_ES.UTF-8

COPY entrypoint.sh /entrypoint.sh
# Quitar CRLF y hacer ejecutable
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

RUN apk update && \
    apk add --no-cache \
        git openssh ca-certificates musl-dev \
        gcc make ncurses-libs ncurses-dev \
        mariadb-dev mariadb-client \
        perl perl-dev perl-utils perl-dbd-mysql \
        perl-db_file perl-digest-sha1 perl-io-socket-ssl \
        perl-net-telnet perl-timedate perl-yaml-libyaml \
        perl-test-simple perl-app-cpanminus \
        perl-libwww perl-lwp-protocol-https \
        wget curl bash nano \
        perl-net-smtp-ssl tini \
        gettext libintl \
        openssl-dev zlib-dev \
        --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing \
        musl-locales musl-locales-lang && \
    echo "export LANG=es_ES.UTF-8" >> /etc/profile && \
    echo "export LC_ALL=es_ES.UTF-8" >> /etc/profile && \
    # Instalar módulos Perl adicionales
    cpanm --no-wget Curses Date::Manip && \
    cpanm EV Mojolicious JSON JSON::XS Data::Structure::Util && \
    cpanm Math::Round List::MoreUtils Date::Calc && \
    cpanm Net::MQTT::Simple Net::CIDR::Lite && \
    cpanm File::Copy::Recursive Authen::SASL && \
    # DBI se instala desde cpanm; DBD::mysql ya viene desde apk
    cpanm DBI && \
    # Crear usuario spider
    adduser -D -u $SPIDER_UID -h /spider $SPIDER_USERNAME && \
    git config --global --add safe.directory /spider && \
    # Clonar DXSpider
    git clone git://scm.dxcluster.org/scm/spider -b mojo /spider && \
    cd /spider && \
    git reset --hard && \
    git pull && \
    # Limpiar
    apk del --purge gcc make musl-dev ncurses-dev perl-app-cpanminus perl-dev && \
    rm -rf /var/cache/apk/* && \
    rm -rf /root/.cpanm && \
    rm -rf /resources

ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]

