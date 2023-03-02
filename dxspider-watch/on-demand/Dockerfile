#
#   Modify by Kin EA3CV
#
#   Docker personalizado para la versión 1.57 (rama mojo) y para EA4URE-2
#
#   Adapted for DXSpider 1.57 installation
#   20230201  v1.3
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

FROM alpine:3.12

ENV SPIDER_USERNAME=${SPIDER_USERNAME:-sysop} SPIDER_UID=${SPIDER_UID:-1000}

COPY entrypoint.sh /entrypoint.sh

RUN apk update && \
    apk add --update --no-cache git musl-dev \
        gcc make \
        ncurses-libs ncurses-dev \
        perl-db_file perl-dev perl-digest-sha1 perl-io-socket-ssl \
        perl-net-telnet perl-timedate perl-yaml-libyaml \
        perl-test-simple perl-app-cpanminus \
        wget curl perl bash nano \
        tini tg && \
    cpanm --no-wget Curses Date::Manip && \
    cpanm EV Mojolicious JSON JSON::XS Data::Structure::Util && \
    cpanm Math::Round List::MoreUtils Date::Calc && \
    cpanm Net::MQTT::Simple Net::CIDR::Lite && \
    cpanm File::Copy::Recursive && \
    cpanm File::Copy::Recursive && \
    adduser -D -u $SPIDER_UID -h /spider $SPIDER_USERNAME && \
    git clone git://scm.dxcluster.org/scm/spider -b mojo /spider &&  \
    cd /spider && \

    git reset --hard && \
    git pull && \

#   Descomentar para generar una imágen concreta a un commit
#
#    git checkout cc9bd946788545ef87a7a6d0541fa1c47b9b034a && \
#
#
    (cd /spider/src && make) && \

    apk del --purge gcc make musl-dev ncurses-dev perl-app-cpanminus perl-dev && \
    rm -rf /var/cache/apk/* && \
    rm -rf /resources

ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
