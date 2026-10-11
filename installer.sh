#!/bin/bash
# Загрузчик: кладёт скрипт управления в /home/zapret/installer и запускает его.
# Запуск на Деке (в Konsole, от пользователя deck):
#   bash <(curl -fsSL https://raw.githubusercontent.com/k0kfjjfkdjf/decke-port_Snowy-Fluffy-zapret/main/installer.sh)
#
# Ни read-only, ни pacman здесь не трогаются: всё живёт в /home и /etc.

set -e

ZBASE="/home/zapret"
DEST="$ZBASE/installer"
SLUG="k0kfjjfkdjf/decke-port_Snowy-Fluffy-zapret"
BRANCH="main"

if [[ $EUID -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
        echo "sudo не найден"; exit 1
    fi
    if ! sudo -v; then
        echo "Нужен пароль sudo. Если он не задан, выполните: passwd"
        exit 1
    fi
    SUDO=sudo
else
    SUDO=""
fi

$SUDO mkdir -p "$ZBASE"
$SUDO chmod 755 "$ZBASE"
TMP="$($SUDO mktemp -d "$ZBASE/.tmp.XXXXXX")"
cleanup() { $SUDO rm -rf "$TMP"; }
trap cleanup EXIT

echo "==> Загружаю скрипт управления..."
if command -v git >/dev/null 2>&1 && $SUDO git clone --depth 1 -b "$BRANCH" "https://github.com/$SLUG.git" "$TMP/repo" >/dev/null 2>&1; then
    :
else
    $SUDO mkdir -p "$TMP/repo"
    curl -fsSL --retry 3 "https://codeload.github.com/$SLUG/tar.gz/refs/heads/$BRANCH" \
        | $SUDO tar -xz -C "$TMP/repo" --strip-components=1
fi

[[ -f $TMP/repo/zapret-control.sh ]] || { echo "Не удалось загрузить скрипт"; exit 1; }
$SUDO rm -rf "$DEST"
$SUDO mv "$TMP/repo" "$DEST"
$SUDO chown -R root:root "$DEST"
$SUDO chmod +x "$DEST/zapret-control.sh" "$DEST/installer.sh"

trap - EXIT
cleanup
exec $SUDO bash "$DEST/zapret-control.sh"
