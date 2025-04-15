#!/bin/bash

source /root/dxspider-watch/157.ver

cd /root/dxspider-watch/spider

echo 'Última versión: '$VERSION | ts '[%Y-%m-%d %H:%M:%S]'

#git checkout mojo | ts '[%Y-%m-%d %H:%M:%S]'
#git pull | ts '[%Y-%m-%d %H:%M:%S]'

GITVERSION=$(git describe --long | cut -d'-' -f2)

echo 'Versión en repositorio: '$GITVERSION | ts '[%Y-%m-%d %H:%M:%S]'

git remote update

UPSTREAM=${1:-'@{u}'}
LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse "$UPSTREAM")

if [ $LOCAL = $REMOTE ]; then
    echo "No hay nueva release en Mojo." | ts '[%Y-%m-%d %H:%M:%S]'
elif [ $LOCAL != $REMOTE ]; then
    echo "Detectada nueva Release de Mojo" | ts '[%Y-%m-%d %H:%M:%S]'

    git reset --hard origin/mojo
    git pull

    GITVERSION=$(git describe --long | cut -d'-' -f2)

    ID="@dxspider"
    TOKEN="1376233105:AAHOfU_M97j1gXm1l4xLPpmF_v6CYCxIL3M"
    PAYLOAD="*Mojo*   🆕  *UPDATE build $GITVERSION*"

    URL="https://api.telegram.org/bot$TOKEN/sendMessage"
    curl -s -X POST $URL -d chat_id=$ID -d text="$PAYLOAD" -d parse_mode="Markdown"

    cd /root/dxspider-watch/mojo
    docker build --no-cache -t dxspider:v157r$GITVERSION .
    cd /root/dxspider-watch/spider
    git describe --long | cut -d'-' -f2 | xargs -I {} echo "VERSION="{} > /root/dxspider-watch/157.ver
    cd /root/dxspider-watch

fi
