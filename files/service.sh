#!/bin/bash
# На SteamOS только systemd, поэтому без openrc/runit/procd из оригинала.

write_unit() {
    cat > "$UNIT_FILE" <<EOF
[Unit]
Description=zapret DPI bypass (Steam Deck port)
After=network-online.target
Wants=network-online.target
RequiresMountsFor=$ZBASE

[Service]
Type=forking
Restart=no
TimeoutSec=30sec
IgnoreSIGPIPE=no
GuessMainPID=no
RemainAfterExit=no
ExecStart=$ZAPRET_DIR/init.d/sysv/zapret start
ExecStop=$ZAPRET_DIR/init.d/sysv/zapret stop

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "$UNIT_FILE"
    write_keep_list
    systemctl daemon-reload
}

# С SteamOS 3.6 обновление переносит из /etc только файлы из белого списка.
# Юниты *.service и *.wants там уже есть по умолчанию, но добавим свои явно,
# на случай если Valve изменит стандартный список.
KEEP_LIST="/etc/atomic-update.conf.d/zapret.conf"
write_keep_list() {
    [[ -d /etc/atomic-update.conf.d ]] || return 0
    cat > "$KEEP_LIST" <<EOF
# zapret (Steam Deck port): сохранить сервис при обновлениях SteamOS
$UNIT_FILE
/etc/systemd/system/multi-user.target.wants/zapret.service
EOF
    chmod 644 "$KEEP_LIST"
}

# Хвосты от установки оригинальным скриптом в /opt: после обновления
# SteamOS они указывают в пустоту.
cleanup_legacy_units() {
    local f found=0
    for f in /etc/systemd/system/timers.target.wants/zapret-list-update.timer \
             /etc/systemd/system/zapret-list-update.timer \
             /etc/systemd/system/zapret-list-update.service; do
        if [[ -e $f || -L $f ]]; then
            found=1
            rm -f "$f"
        fi
    done
    if [[ -f $UNIT_FILE ]] && grep -q "$ORIG_ZAPRET_DIR/" "$UNIT_FILE"; then
        found=1
    fi
    if (( found )); then
        msg "Убираю юниты от старой установки в $ORIG_ZAPRET_DIR..."
        systemctl stop zapret-list-update.timer zapret >/dev/null 2>&1
        systemctl disable zapret >/dev/null 2>&1
        systemctl daemon-reload
    fi
    # битая ссылка автозагрузки на удалённый юнит из /usr
    f=/etc/systemd/system/multi-user.target.wants/zapret.service
    if [[ -L $f && ! -e $f ]]; then
        rm -f "$f"
    fi
    return 0
}

manage_service() {
    SYSTEMD_PAGER=cat systemctl "$1" "$UNIT_NAME"
}

manage_autostart() {
    systemctl "$1" "$UNIT_NAME"
}

check_zapret_status() {
    local active sub enabled
    active="$(systemctl show -p ActiveState --value "$UNIT_NAME" 2>/dev/null)"
    sub="$(systemctl show -p SubState --value "$UNIT_NAME" 2>/dev/null)"
    enabled="$(systemctl is-enabled "$UNIT_NAME" 2>/dev/null)"
    [[ $active == active && $sub == running ]] && ZAPRET_ACTIVE=true || ZAPRET_ACTIVE=false
    [[ $enabled == enabled ]] && ZAPRET_ENABLED=true || ZAPRET_ENABLED=false
}

# Установлен = файлы в /home на месте. Юнит в /etc проверяется отдельно:
# если пропал только он (обновление SteamOS), его можно пересоздать.
check_zapret_exist() {
    MISSING=()
    [[ -d $ZAPRET_DIR ]] || MISSING+=("каталог $ZAPRET_DIR")
    [[ -f $ZAPRET_DIR/init.d/sysv/zapret ]] || MISSING+=("$ZAPRET_DIR/init.d/sysv/zapret")
    [[ -x $ZAPRET_DIR/nfq/nfqws ]] || MISSING+=("$ZAPRET_DIR/nfq/nfqws")
    [[ -f $ZAPRET_CONFIG ]] || MISSING+=("$ZAPRET_CONFIG")
    if (( ${#MISSING[@]} == 0 )); then
        ZAPRET_EXIST=true
    else
        ZAPRET_EXIST=false
    fi
    if [[ -f $UNIT_FILE ]] && grep -q "$ZAPRET_DIR/init.d/sysv/zapret" "$UNIT_FILE"; then
        UNIT_OK=true
    else
        UNIT_OK=false
    fi
}

nfqws_running() {
    NFQWS_PIDS="$(pgrep -d ' ' -x nfqws 2>/dev/null)"
    [[ -n $NFQWS_PIDS ]]
}

# Следы установки оригинальным скриптом (в /opt)
legacy_install_hint() {
    if [[ -d $ORIG_ZAPRET_DIR || -d /opt/zapret.installer || -e /bin/zapret ]]; then
        echo -e "  ${C_YEL}Найдены следы оригинального установщика (/opt/zapret, /bin/zapret).${C_RST}"
        echo -e "  ${C_YEL}Команда 'zapret' могла запускать его, а не этот порт.${C_RST}"
    fi
}

# Пересоздать юнит, если файлы на месте, а юнит пропал или устарел
repair_unit_if_needed() {
    [[ $ZAPRET_EXIST == true && $UNIT_OK == false ]] || return 0
    msg "Сервис zapret не найден в /etc или указывает не туда — пересоздаю..."
    write_unit
    manage_autostart enable >/dev/null 2>&1
    manage_service restart
    check_zapret_exist
    check_zapret_status
    sleep 1
}

toggle_service() {
    while true; do
        clear
        check_zapret_status
        echo -e "${C_CYN}╔═════════════════════════════════════════════════╗"
        echo -e "║         Управление сервисом Запрета             ║"
        echo -e "╚═════════════════════════════════════════════════╝${C_RST}"
        [[ $ZAPRET_ACTIVE == true ]] && echo -e "  ${C_GRN}Запрет запущен${C_RST}" || echo -e "  ${C_RED}Запрет выключен${C_RST}"
        [[ $ZAPRET_ENABLED == true ]] && echo -e "  ${C_GRN}Запрет в автозагрузке${C_RST}" || echo -e "  ${C_YEL}Запрет не в автозагрузке${C_RST}"
        echo
        echo -e "  ${C_RED}0)${C_RST} Выйти в меню"
        echo -e "  ${C_YEL}1)${C_RST} $([[ $ZAPRET_ENABLED == true ]] && echo "Убрать из автозагрузки" || echo "Добавить в автозагрузку")"
        echo -e "  ${C_GRN}2)${C_RST} $([[ $ZAPRET_ACTIVE == true ]] && echo "Выключить Запрет" || echo "Включить Запрет")"
        echo -e "  ${C_CYN}3)${C_RST} Посмотреть статус Запрета"
        echo -e "  ${C_MAG}4)${C_RST} Перезапустить Запрет"
        echo -e "  ${C_BLU}5)${C_RST} Последние строки журнала"
        echo
        read -rp $'\e[1;36mВыберите действие: \e[0m' CHOICE
        case "$CHOICE" in
            1) [[ $ZAPRET_ENABLED == true ]] && manage_autostart disable || manage_autostart enable ;;
            2) [[ $ZAPRET_ACTIVE == true ]] && manage_service stop || manage_service start ;;
            3) manage_service status; pause ;;
            4) manage_service restart ;;
            5) journalctl -u "$UNIT_NAME" -n 40 --no-pager; pause ;;
            0) return ;;
            *) echo -e "${C_RED}Неверный ввод! Попробуйте снова.${C_RST}"; sleep 2 ;;
        esac
    done
}
