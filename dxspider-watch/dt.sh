#!/bin/bash
source /root/dxspider-watch/157.ver

cd /root/dxspider-watch/spider

echo 'Última versión: '$VERSION | ts '[%Y-%m-%d %H:%M:%S]'

git checkout mojo | ts '[%Y-%m-%d %H:%M:%S]'

git pull | ts '[%Y-%m-%d %H:%M:%S]'

GITVERSION=$(git describe --long | cut -d'-' -f2)

echo 'Versión en repositorio: '$GITVERSION | ts '[%Y-%m-%d %H:%M:%S]'

if [[ $VERSION = $GITVERSION ]]
then
    echo "No hay nueva release en Mojo." | ts '[%Y-%m-%d %H:%M:%S]'
else
    echo "Detectada nueva Release de Mojo" | ts '[%Y-%m-%d %H:%M:%S]'
    cd /root/dxspider-watch/mojo
    docker build --no-cache -t dxspider:v157r$GITVERSION .
    cd /root/dxspider-watch/spider
    git describe --long | cut -d'-' -f2 | xargs -I {} echo "VERSION="{} > /root/dxspider-watch/157.ver
    cd /root/dxspider-watch
fi
