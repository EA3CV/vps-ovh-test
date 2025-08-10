#!/bin/bash

source /root/dxspider-watch/157.ver

cd /root/dxspider-watch/spider

echo 'Última versión: '$VERSION | ts '[%Y-%m-%d %H:%M:%S]'

git fetch origin
git checkout -B mojo origin/mojo | ts '[%Y-%m-%d %H:%M:%S]'
#git checkout mojo | ts '[%Y-%m-%d %H:%M:%S]'

git pull | ts '[%Y-%m-%d %H:%M:%S]'

GITVERSION=$(git describe --long | cut -d'-' -f2)

echo 'Versión en repositorio: '$GITVERSION | ts '[%Y-%m-%d %H:%M:%S]'

if [[ $VERSION = $GITVERSION ]]
then
    echo "No hay nueva release en Mojo." | ts '[%Y-%m-%d %H:%M:%S]'
    rm payload.msg
else
    echo "Detectada nueva Release de Mojo" | ts '[%Y-%m-%d %H:%M:%S]'
    cd /root/dxspider-watch/demanda
    docker build --no-cache -t dxspider:v157r633-Test .
fi
