#!/bin/bash
# Меню управления zapret — порт Snowy-Fluffy/zapret.installer для Steam Deck.
# Всё ставится в /home/zapret, сервис — /etc/systemd/system/zapret.service,
# поэтому обновления SteamOS установку не ломают.

SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
HERE="$(dirname "$SCRIPT")"

if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        if ! sudo -v; then
            echo "Нужен пароль sudo. Если он не задан, выполните: passwd"
            exit 1
        fi
        exec sudo bash "$SCRIPT" "$@"
    fi
    echo "Скрипт нужно запускать от имени суперпользователя."
    exit 1
fi

for f in paths utils fw service config install menu; do
    # shellcheck source=/dev/null
    source "$HERE/files/$f.sh" || { echo "Не найден $HERE/files/$f.sh"; exit 1; }
done

trap fast_exit INT
check_tput
detect_target_user
is_steamos || warn "Это не SteamOS. Скрипт рассчитан на Steam Deck, но продолжу."
$TPUT_B
main_menu
