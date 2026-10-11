#!/bin/bash

C_RED=$'\e[1;31m'; C_GRN=$'\e[1;32m'; C_YEL=$'\e[1;33m'; C_BLU=$'\e[1;34m'
C_MAG=$'\e[1;35m'; C_CYN=$'\e[1;36m'; C_RST=$'\e[0m'

msg()  { echo -e "${C_CYN}==>${C_RST} $*"; }
ok()   { echo -e "${C_GRN}✔${C_RST} $*"; }
warn() { echo -e "${C_YEL}⚠${C_RST} $*" >&2; }
err()  { echo -e "${C_RED}Ошибка:${C_RST} $*" >&2; }

error_exit() {
    $TPUT_E
    err "$1"
    exit 1
}

pause() { read -rp $'\e[1;36mНажмите Enter для продолжения...\e[0m' _; }

# ask_yn "вопрос" Y|N  -> 0 если да
ask_yn() {
    local q="$1" def="${2:-N}" a hint="(y/N)"
    [[ $def == Y ]] && hint="(Y/n)"
    read -rp "$q $hint: " a
    a="${a:-$def}"
    [[ $a == [YyДд]* ]]
}

exists() { command -v "$1" >/dev/null 2>&1; }

check_tput() {
    if exists tput && [[ -t 1 ]]; then
        TPUT_B="tput smcup"; TPUT_E="tput rmcup"
    else
        TPUT_B=""; TPUT_E=""
    fi
}

fast_exit() {
    $TPUT_E
    echo "Выход по запросу пользователя"
    exit 130
}

# Пользователь, от имени которого запущен скрипт (для ярлыков в его $HOME)
detect_target_user() {
    TARGET_USER="${SUDO_USER:-}"
    if [[ -z $TARGET_USER || $TARGET_USER == root ]]; then
        TARGET_USER="$(logname 2>/dev/null || true)"
    fi
    if [[ -z $TARGET_USER || $TARGET_USER == root ]]; then
        TARGET_USER="deck"
    fi
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    [[ -n $TARGET_HOME ]] || TARGET_HOME="/home/$TARGET_USER"
}

is_steamos() {
    [[ -f /etc/os-release ]] && grep -qiE '^ID=("?)steamos' /etc/os-release
}

mk_tmp() { mkdir -p "$ZBASE" && mktemp -d "$ZBASE/.tmp.XXXXXX"; }

# Скачать репозиторий GitHub в каталог (git, если есть, иначе tar.gz).
# Старый каталог заменяется только после успешной загрузки.
fetch_repo() {
    local slug="$1" branch="$2" dest="$3" tmp sub

    if exists git && [[ -d $dest/.git ]]; then
        if git -C "$dest" fetch --depth 1 origin "$branch" >/dev/null 2>&1 \
           && git -C "$dest" reset --hard FETCH_HEAD >/dev/null 2>&1; then
            return 0
        fi
        warn "git не смог обновить $dest, качаю заново"
    fi

    tmp="$(mk_tmp)" || return 1
    if exists git; then
        if git clone --depth 1 -b "$branch" "https://github.com/$slug.git" "$tmp/repo" >/dev/null 2>&1; then
            rm -rf "$dest" && mv "$tmp/repo" "$dest"
            rm -rf "$tmp"
            return 0
        fi
        warn "git clone не удался, пробую архивом"
        rm -rf "$tmp/repo"
    fi

    if curl -fsSL --retry 3 --max-time 120 \
         "https://codeload.github.com/$slug/tar.gz/refs/heads/$branch" | tar -xz -C "$tmp"; then
        sub="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n1)"
        if [[ -n $sub ]]; then
            rm -rf "$dest" && mv "$sub" "$dest"
            rm -rf "$tmp"
            return 0
        fi
    fi
    rm -rf "$tmp"
    return 1
}

open_editor() {
    local file="$1" ed
    [[ -f $file ]] || touch "$file"
    for ed in "${EDITOR:-}" "${VISUAL:-}" nano vim vi nvim helix; do
        [[ -n $ed ]] || continue
        if exists "$ed"; then
            "$ed" "$file"
            return 0
        fi
    done
    warn "Не найден текстовый редактор (nano, vim, vi). Файл: $file"
    pause
    return 1
}

# Нормализовать ввод "a.com, b.com | 1.2.3.4" в массив ADDRESSES
parse_addresses() {
    local input="$1" a
    ADDRESSES=()
    IFS=',| ' read -ra _parts <<< "$input"
    for a in "${_parts[@]}"; do
        a="${a//[[:space:]]/}"
        [[ -n $a ]] && ADDRESSES+=("$a")
    done
}
