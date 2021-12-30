#!/bin/bash
source /root/spider-watch/157.ver

cd /root/spider-watch/spider

git checkout mojo
git pull
GITVERSION=$(git describe --long | cut -d'-' -f2)

cd /root/spider-watch

if [[ $VERSION = $GITVERSION ]]
then
    echo "No hay nueva version en Mojo"
else
    echo "Hay nueva version en Mojo"
    cd /root/spider-watch/mojo
    docker build --no-cache -t dxspider:v157r$GITVERSION .
    cd /root/spider-watch/spider
    git describe --long | cut -d'-' -f2 | xargs -I {} echo "VERSION="{} > /root/spider-watch/157.ver
    cd /root/spider-watch
fi
