#!/bin/bash
source /root/dxspider-watch/157.ver

cd /root/dxspider-watch/spider

git checkout mojo
git pull
GITVERSION=$(git describe --long | cut -d'-' -f2)

cd /root/dxspider-watch

if [[ $VERSION = $GITVERSION ]]
then
    echo "No hay nueva version en Mojo"
else
    echo "Hay nueva version en Mojo"
    cd /root/dxspider-watch/mojo
    docker build --no-cache -t dxspider:v157r$GITVERSION .
    cd /root/dxspider-watch/spider
    git describe --long | cut -d'-' -f2 | xargs -I {} echo "VERSION="{} > /root/dxspider-watch/157.ver
    cd /root/dxspider-watch
fi
