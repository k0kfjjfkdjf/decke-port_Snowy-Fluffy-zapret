#!/bin/bash
# Файрвол и ядро.
# Сам zapret ставится в /home и переживает обновления SteamOS. Единственное,
# что может пропасть после обновления, — nft, если его доставляли через pacman.

detect_fwtype() {
    if exists nft; then
        FWTYPE=nftables
    elif exists iptables && exists ip6tables; then
        FWTYPE=iptables
    else
        FWTYPE=""
    fi
}

fw_status_text() {
    detect_fwtype
    if [[ -n $FWTYPE ]]; then
        echo "${C_GRN}$FWTYPE${C_RST}"
    else
        echo "${C_RED}не найден (нужен nft или iptables)${C_RST}"
    fi
}

check_kernel_modules() {
    local m missing=()
    for m in nfnetlink_queue; do
        if ! modprobe -q "$m" 2>/dev/null && ! grep -qw "$m" /proc/modules 2>/dev/null; then
            # модуль может быть встроен в ядро — тогда modprobe ничего не найдёт, но всё работает
            [[ -d /sys/module/$m ]] || missing+=("$m")
        fi
    done
    if (( ${#missing[@]} )); then
        warn "Не удалось найти модуль ядра: ${missing[*]}. nfqws может не запуститься."
        return 1
    fi
    return 0
}

# Доставить пакеты через pacman правильно: ключи вместо SigLevel=Never,
# read-only возвращается в исходное состояние.
pacman_install() {
    local was_ro=0 rc=0
    exists pacman || { err "pacman не найден"; return 1; }

    if exists steamos-readonly && steamos-readonly status 2>/dev/null | grep -q '^enabled'; then
        was_ro=1
        msg "Временно отключаю read-only..."
        steamos-readonly disable || return 1
    fi

    if [[ ! -s /etc/pacman.d/gnupg/trustdb.gpg ]]; then
        msg "Инициализирую связку ключей pacman..."
        pacman-key --init || rc=1
    fi
    if (( rc == 0 )); then
        msg "Загружаю ключи Arch и Valve (holo)..."
        pacman-key --populate archlinux holo || pacman-key --populate archlinux || rc=1
    fi
    if (( rc == 0 )); then
        msg "Устанавливаю: $*"
        pacman -Sy --needed --noconfirm "$@" || rc=1
    fi

    if (( was_ro )); then
        msg "Возвращаю read-only..."
        steamos-readonly enable
    fi
    return $rc
}

fw_repair() {
    echo
    warn "В системе нет ни nft, ни iptables+ip6tables."
    echo "Можно поставить nftables через pacman (с нормальной проверкой подписей)."
    echo "После обновления SteamOS его, возможно, придётся поставить снова —"
    echo "для этого в главном меню появится отдельный пункт."
    if ask_yn "Установить nftables сейчас?" Y; then
        pacman_install nftables && detect_fwtype
    fi
    [[ -n $FWTYPE ]]
}

# Прописать FWTYPE в конфиг zapret
set_config_fwtype() {
    local cfg="${1:-$ZAPRET_CONFIG}"
    detect_fwtype
    [[ -n $FWTYPE ]] || FWTYPE=nftables
    if grep -q '^FWTYPE=' "$cfg"; then
        sed -i "s/^FWTYPE=.*/FWTYPE=$FWTYPE/" "$cfg"
    else
        echo "FWTYPE=$FWTYPE" >> "$cfg"
    fi
}
