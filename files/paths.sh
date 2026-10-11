#!/bin/bash
# Все пути порта в одном месте.
# Всё живёт в /home (раздел home не затирается обновлениями SteamOS),
# юнит systemd — в /etc (на SteamOS /etc сохраняется при обновлениях).
# Каталог принадлежит root и открыт на чтение всем: демоны zapret
# сбрасывают права до пользователя tpws и должны читать списки.

ZBASE="${ZBASE:-/home/zapret}"
ZAPRET_DIR="$ZBASE/zapret"            # релиз bol-van/zapret
CFGS_DIR="$ZBASE/zapret.cfgs"         # стратегии и списки Snowy-Fluffy
INSTALLER_DIR="$ZBASE/installer"      # этот скрипт
CUSTOM_DIR="$ZBASE/custom"            # свои стратегии и списки (не трогаются обновлениями)
STATE_DIR="$ZBASE/state"              # что сейчас применено
VER_FILE="$ZBASE/zapret-ver"

IPSET_DIR="$ZAPRET_DIR/ipset"
HOSTS_USER="$IPSET_DIR/zapret-hosts-user.txt"
HOSTS_EXCLUDE="$IPSET_DIR/zapret-hosts-user-exclude.txt"
IPSET_GAME="$IPSET_DIR/ipset-game.txt"
IPSET_DISCORD="$IPSET_DIR/ipset-discord.txt"
FAKE_DIR="$ZAPRET_DIR/files/fake"
ZAPRET_CONFIG="$ZAPRET_DIR/config"

CUSTOM_CONF="$CUSTOM_DIR/conf-custom"
CUSTOM_LIST="$CUSTOM_DIR/list-custom.txt"

UNIT_NAME="zapret"
UNIT_FILE="${UNIT_FILE:-/etc/systemd/system/zapret.service}"

# Откуда всё качается
INSTALLER_SLUG="k0kfjjfkdjf/decke-port_Snowy-Fluffy-zapret"
INSTALLER_BRANCH="main"
CFGS_SLUG="Snowy-Fluffy/zapret.cfgs"
CFGS_BRANCH="main"
ZAPRET_SLUG="bol-van/zapret"

# Пути, которые зашиты в стратегиях оригинала
ORIG_ZAPRET_DIR="/opt/zapret"
