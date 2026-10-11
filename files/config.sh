#!/bin/bash
# Стратегии, хостлисты, игровой режим, автоподбор стратегии.

# В стратегиях Snowy-Fluffy зашиты пути /opt/zapret/... — переписываем на наши.
rewrite_paths() {
    local f="$1"
    sed -i "s#${ORIG_ZAPRET_DIR}\(/\|\"\|'\| \|\$\)#${ZAPRET_DIR}\1#g" "$f"
}

save_state() { mkdir -p "$STATE_DIR"; printf '%s\n' "$2" > "$STATE_DIR/$1"; }
read_state() { [[ -f $STATE_DIR/$1 ]] && cat "$STATE_DIR/$1"; }
file_sha()   { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# apply_strategy_file <файл> <имя> — без перезапуска сервиса
apply_strategy_file() {
    local src="$1" name="$2" tmp="$ZAPRET_CONFIG.new"
    [[ -f $src ]] || { err "Файл стратегии не найден: $src"; return 1; }
    cp -- "$src" "$tmp" || return 1
    rewrite_paths "$tmp"
    set_config_fwtype "$tmp"
    chmod 644 "$tmp"
    mv -f "$tmp" "$ZAPRET_CONFIG"
    save_state strategy "$name"
    save_state strategy.sha "$(file_sha "$ZAPRET_CONFIG")"
}

apply_strategy_by_name() {
    local name="$1"
    if [[ $name == conf-custom ]]; then
        apply_strategy_file "$CUSTOM_CONF" "$name"
    else
        apply_strategy_file "$CFGS_DIR/configurations/$name" "$name"
    fi
}

apply_list_file() {
    local src="$1" name="$2"
    [[ -f $src ]] || { err "Файл хостлиста не найден: $src"; return 1; }
    cp -- "$src" "$HOSTS_USER" || return 1
    chmod 644 "$HOSTS_USER"
    save_state list "$name"
}

apply_list_by_name() {
    local name="$1"
    if [[ $name == list-custom.txt ]]; then
        apply_list_file "$CUSTOM_LIST" "$name"
    else
        apply_list_file "$CFGS_DIR/lists/$name" "$name"
    fi
}

cur_conf() {
    local name sha
    name="$(read_state strategy)"
    sha="$(read_state strategy.sha)"
    if [[ -z $name ]]; then
        cr_cnf="неизвестно"
    elif [[ -n $sha && $sha != "$(file_sha "$ZAPRET_CONFIG")" ]]; then
        cr_cnf="$name (изменена вручную)"
    else
        cr_cnf="$name"
    fi
}

cur_list() {
    cr_lst="$(read_state list)"
    [[ -n $cr_lst ]] || cr_lst="неизвестно"
}

list_strategies() {
    STRATEGIES=()
    local f
    for f in "$CFGS_DIR"/configurations/*; do
        [[ -f $f ]] && STRATEGIES+=("$(basename "$f")")
    done
    [[ -f $CUSTOM_CONF ]] && STRATEGIES+=("conf-custom")
}

list_hostlists() {
    HOSTLISTS=()
    local f
    for f in "$CFGS_DIR"/lists/list*; do
        [[ -f $f ]] && HOSTLISTS+=("$(basename "$f")")
    done
    [[ -f $CUSTOM_LIST ]] && HOSTLISTS+=("list-custom.txt")
}

# choose_from "подсказка" элементы... -> CHOSEN, код 1 при отмене
choose_from() {
    local PS3="$1"; shift
    CHOSEN=""
    select CHOSEN in "$@" "Отмена"; do
        [[ $CHOSEN == "Отмена" ]] && return 1
        [[ -n $CHOSEN ]] && return 0
        echo -e "${C_RED}Неверный выбор, попробуйте снова.${C_RST}"
    done
    return 1
}

configure_zapret_conf() {
    clear
    list_strategies
    (( ${#STRATEGIES[@]} )) || { err "Стратегии не найдены в $CFGS_DIR"; pause; return; }
    echo "Выберите стратегию (можно поменять в любой момент через меню):"
    choose_from "Введите номер стратегии: " "${STRATEGIES[@]}" || return
    if apply_strategy_by_name "$CHOSEN"; then
        ok "Стратегия '$CHOSEN' установлена."
        manage_service restart
    fi
    sleep 2
}

configure_zapret_list() {
    clear
    list_hostlists
    (( ${#HOSTLISTS[@]} )) || { err "Хостлисты не найдены в $CFGS_DIR"; pause; return; }
    echo -e "${C_CYN}Выберите хостлист:${C_RST}"
    choose_from "Введите номер листа: " "${HOSTLISTS[@]}" || return
    if apply_list_by_name "$CHOSEN"; then
        ok "Хостлист '$CHOSEN' установлен."
        manage_service restart
    fi
    sleep 2
}

configure_custom_conf_path() {
    local path
    echo -e "${C_CYN}Укажите путь к стратегии (пустой ввод — отмена)${C_RST}"
    read -rp "Путь к стратегии: " path
    [[ -n $path ]] || return
    path="${path/#\~/$TARGET_HOME}"
    if [[ ! -f $path ]]; then
        err "Файл не найден: $path"; sleep 2; return
    fi
    apply_strategy_file "$path" "$(basename "$path") (из файла)" && {
        ok "Стратегия установлена из: $path"
        manage_service restart
    }
    sleep 2
}

configure_custom_list_path() {
    local path
    echo -e "${C_CYN}Укажите путь к хостлисту (пустой ввод — отмена)${C_RST}"
    read -rp "Путь к хостлисту: " path
    [[ -n $path ]] || return
    path="${path/#\~/$TARGET_HOME}"
    if [[ ! -f $path ]]; then
        err "Файл не найден: $path"; sleep 2; return
    fi
    apply_list_file "$path" "$(basename "$path") (из файла)" && {
        ok "Хостлист установлен из: $path"
        manage_service restart
    }
    sleep 2
}

# ---- операции со списками ---------------------------------------------------

add_to_list() {
    local file="$1" what="$2" input a
    read -rp "Введите IP или домены для добавления в $what (через пробел, запятую или |; пусто — отмена): " input
    [[ -n $input ]] || return
    parse_addresses "$input"
    touch "$file"
    for a in "${ADDRESSES[@]}"; do
        if grep -Fxq -- "$a" "$file"; then
            echo "Уже есть: $a"
        else
            # дописываем перевод строки, если файл им не заканчивается
            [[ -s $file && -n $(tail -c1 "$file") ]] && echo >> "$file"
            echo "$a" >> "$file"
            echo "Добавлено: $a"
        fi
    done
    manage_service restart
    echo "Готово"; sleep 2
}

delete_from_list() {
    local file="$1" what="$2" input a tmp
    read -rp "Введите IP или домены для удаления из $what (пусто — отмена): " input
    [[ -n $input ]] || return
    parse_addresses "$input"
    for a in "${ADDRESSES[@]}"; do
        if grep -Fxq -- "$a" "$file" 2>/dev/null; then
            tmp="$(mktemp)"
            grep -vFx -- "$a" "$file" > "$tmp"
            cat "$tmp" > "$file"
            rm -f "$tmp"
            echo "Удалено: $a"
        else
            echo "Не найдено: $a"
        fi
    done
    manage_service restart
    echo "Готово"; sleep 2
}

search_in_list() {
    local file="$1" kw
    read -rp "Введите домен или IP для поиска (пусто — отмена): " kw
    [[ -n $kw ]] || return
    echo
    echo "🔍 Результаты поиска: $kw"
    echo "----------------------------------------"
    grep -i --color=never -F -- "$kw" "$file" 2>/dev/null || echo "❌ Совпадений не найдено."
    echo "----------------------------------------"
    pause
}

edit_and_restart() {
    open_editor "$1" && manage_service restart
}

edit_cust_list() {
    mkdir -p "$CUSTOM_DIR"
    [[ -f $CUSTOM_LIST ]] || touch "$CUSTOM_LIST"
    open_editor "$CUSTOM_LIST" || return
    chmod 644 "$CUSTOM_LIST"
    echo "Кастомный хостлист сохранён: $CUSTOM_LIST"
    if ask_yn "Применить его сейчас?" Y; then
        apply_list_by_name list-custom.txt && manage_service restart
    fi
}

edit_cust_conf() {
    mkdir -p "$CUSTOM_DIR"
    if [[ ! -f $CUSTOM_CONF ]]; then
        if [[ -f $ZAPRET_CONFIG ]]; then
            cp "$ZAPRET_CONFIG" "$CUSTOM_CONF"
        else
            cp "$ZAPRET_DIR/config.default" "$CUSTOM_CONF"
        fi
    fi
    open_editor "$CUSTOM_CONF" || return
    chmod 644 "$CUSTOM_CONF"
    echo "Кастомная стратегия сохранена: $CUSTOM_CONF"
    if ask_yn "Применить её сейчас?" Y; then
        apply_strategy_by_name conf-custom && manage_service restart
    fi
}

# ---- игровой режим ----------------------------------------------------------

game_mode_check() {
    [[ -f $IPSET_GAME ]] || echo "203.0.113.77" > "$IPSET_GAME"
    if grep -q '^0\.0\.0\.0/0$' "$IPSET_GAME"; then
        game_mode_status="включен"
    else
        game_mode_status="выключен"
    fi
}

toggle_game_mode() {
    game_mode_check
    # 203.0.113.77 — адрес из документационного диапазона, чтобы ipset не был пустым
    if [[ $game_mode_status == "включен" ]]; then
        echo "203.0.113.77" > "$IPSET_GAME"
    else
        echo "0.0.0.0/0" > "$IPSET_GAME"
    fi
    chmod 644 "$IPSET_GAME"
    manage_service restart
    sleep 1
}

# ---- автоподбор стратегии ---------------------------------------------------

# test_domain <домен> -> "ping http tls12 tls13"
test_domain() {
    local d="$1" t r_ping r_http r_12 r_13 t_http=5
    t="$(mktemp -d)"
    if [[ $d =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
        d="${d%%/*}"
        r_ping="$(ping -c 2 -W 2 "$d" 2>/dev/null | awk -F'/' '/rtt|round-trip/ {print $5}')"
        [[ -n $r_ping ]] && r_ping="${r_ping}ms" || r_ping="FAIL"
        echo "$r_ping N/A N/A N/A"
        rm -rf "$t"; return
    fi
    { ping -c 2 -W 2 "$d" 2>/dev/null | awk -F'/' '/rtt|round-trip/ {print $5}' > "$t/ping"; } &
    { curl -m $t_http -s -o /dev/null -w "%{http_code}" "http://$d" > "$t/http" 2>/dev/null; } &
    # https последовательно: оба запроса идут на 443 одного хоста
    r_12="$(curl -m $t_http -s -o /dev/null -w "%{http_code}" --tlsv1.2 --tls-max 1.2 "https://$d" 2>/dev/null)"
    r_13="$(curl -m $t_http -s -o /dev/null -w "%{http_code}" --tlsv1.3 "https://$d" 2>/dev/null)"
    wait
    r_ping="$(cat "$t/ping" 2>/dev/null)"; r_http="$(cat "$t/http" 2>/dev/null)"
    rm -rf "$t"
    [[ -n $r_ping ]] && r_ping="${r_ping}ms" || r_ping="FAIL"
    [[ $r_http =~ ^[1-9][0-9]{2}$ ]] && r_http="HTTP:$r_http" || r_http="FAIL"
    [[ $r_12 =~ ^[1-9][0-9]{2}$ ]] && r_12="TLS1.2:$r_12" || r_12="FAIL"
    [[ $r_13 =~ ^[1-9][0-9]{2}$ ]] && r_13="TLS1.3:$r_13" || r_13="FAIL"
    echo "$r_ping $r_http $r_12 $r_13"
}

# Домен считается доступным, если TLS-рукопожатие прошло и сервер ответил
# (любой код 2xx-4xx). ping на DPI не влияет и часто режется, поэтому не учитывается.
test_all_domains() {
    local name="$1" list="$2" line res total=0 avail=0 is
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│ Стратегия: $name"
    echo "├─────────────────────────────────────────────────────────────────────────────┤"
    printf "│ %-30s │ %-8s │ %-10s │ %-11s │ %-11s │\n" "Домен/IP" "Ping" "HTTP" "TLS1.2" "TLS1.3"
    echo "├─────────────────────────────────────────────────────────────────────────────┤"
    while IFS= read -r line || [[ -n $line ]]; do
        (( STOP_CHECK )) && break
        line="${line%%#*}"; line="${line//[[:space:]]/}"
        [[ -n $line ]] || continue
        total=$((total + 1))
        read -ra res <<< "$(test_domain "$line")"
        is=0
        if [[ $line =~ ^[0-9.]+(/[0-9]+)?$ ]]; then
            [[ ${res[0]} != FAIL ]] && is=1
        elif [[ ${res[2]} =~ ^TLS1\.2:[234] || ${res[3]} =~ ^TLS1\.3:[234] ]]; then
            is=1
        fi
        avail=$((avail + is))
        local shown="$line"; (( ${#shown} > 30 )) && shown="${shown:0:27}..."
        printf "│ %-30s │ %-8s │ %-10s │ %-11s │ %-11s │ %s\n" "$shown" "${res[0]}" "${res[1]}" "${res[2]}" "${res[3]}" \
            "$( (( is )) && echo "${C_GRN}✔${C_RST}" || echo "${C_RED}✘${C_RST}")"
    done < "$list"
    echo "├─────────────────────────────────────────────────────────────────────────────┤"
    echo "│ Доступно: $avail/$total"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    LAST_AVAILABLE=$avail
    LAST_TOTAL=$total
}

# Разбор ввода "1 3 5-7" в индексы
parse_selection() {
    local input="$1" max="$2" part s e i
    SEL=()
    for part in $input; do
        if [[ $part =~ ^([0-9]+)-([0-9]+)$ ]]; then
            s=${BASH_REMATCH[1]}; e=${BASH_REMATCH[2]}
            (( s > e )) && { i=$s; s=$e; e=$i; }
            for ((i = s; i <= e; i++)); do (( i >= 1 && i <= max )) && SEL+=("$i"); done
        elif [[ $part =~ ^[0-9]+$ ]] && (( part >= 1 && part <= max )); then
            SEL+=("$part")
        else
            echo -e "${C_RED}Пропускаю неверный номер: $part${C_RST}"
        fi
    done
    mapfile -t SEL < <(printf '%s\n' "${SEL[@]}" | sort -nu | sed '/^$/d')
}

check_conf() {
    local test_list prev_list_backup prev_list_name i input configs=() stats=() best="" best_n=-1 total=0 cfg
    clear
    list_hostlists
    echo -e "${C_CYN}Выберите хостлист для тестирования (рекомендуется небольшой, например list-basic.txt):${C_RST}"
    choose_from "Введите номер листа: " "${HOSTLISTS[@]}" || return
    if [[ $CHOSEN == list-custom.txt ]]; then test_list="$CUSTOM_LIST"; else test_list="$CFGS_DIR/lists/$CHOSEN"; fi

    total=$(grep -cvE '^[[:space:]]*(#|$)' "$test_list")
    echo "В выбранном листе $total доменов/IP."
    if (( total > 100 )); then
        warn "Проверка займёт *ОЧЕНЬ* много времени."
        ask_yn "Продолжить?" N || return
    fi

    list_strategies
    echo
    echo -e "${C_CYN}Выберите стратегии для проверки:${C_RST}"
    for i in "${!STRATEGIES[@]}"; do printf "  %3d) %s\n" "$((i + 1))" "${STRATEGIES[$i]}"; done
    echo -e "${C_YEL}Номера через пробел и/или диапазоны (например: 1 3 5-9). Пусто — все.${C_RST}"
    read -rp "Стратегии: " input
    if [[ -z $input ]]; then
        configs=("${STRATEGIES[@]}")
    else
        parse_selection "$input" "${#STRATEGIES[@]}"
        for i in "${SEL[@]}"; do configs+=("${STRATEGIES[$((i - 1))]}"); done
    fi
    (( ${#configs[@]} )) || { err "Не выбрано ни одной стратегии"; sleep 2; return; }

    # сохраним текущий хостлист и стратегию, на время теста хостлист = тестовый лист
    prev_list_backup="$(mktemp)"
    cp "$HOSTS_USER" "$prev_list_backup" 2>/dev/null
    prev_list_name="$(read_state list)"
    local prev_conf_backup prev_conf_name prev_conf_sha
    prev_conf_backup="$(mktemp)"
    cp "$ZAPRET_CONFIG" "$prev_conf_backup" 2>/dev/null
    prev_conf_name="$(read_state strategy)"; prev_conf_sha="$(read_state strategy.sha)"
    cp "$test_list" "$HOSTS_USER"

    echo -e "${C_YEL}Будет проверено стратегий: ${#configs[@]}. Ctrl+C — остановить и применить лучшую из проверенных.${C_RST}"
    sleep 3
    STOP_CHECK=0
    trap 'STOP_CHECK=1' INT

    for cfg in "${configs[@]}"; do
        (( STOP_CHECK )) && break
        echo "──────────────────────────────────────────────────────────────────────────────"
        if ! apply_strategy_by_name "$cfg" || ! manage_service restart; then
            err "Не удалось применить стратегию: $cfg"
            continue
        fi
        sleep 2
        test_all_domains "$cfg" "$test_list"
        (( STOP_CHECK )) && break
        stats+=("$cfg|$LAST_AVAILABLE")
        if (( LAST_AVAILABLE > best_n )); then best_n=$LAST_AVAILABLE; best="$cfg"; fi
    done
    trap fast_exit INT

    # хостлист возвращаем как был
    cp "$prev_list_backup" "$HOSTS_USER"; rm -f "$prev_list_backup"
    [[ -n $prev_list_name ]] && save_state list "$prev_list_name"

    if [[ -z $best ]]; then
        warn "Ни одна стратегия не была проверена полностью. Возвращаю прежнюю."
        cp "$prev_conf_backup" "$ZAPRET_CONFIG"
        save_state strategy "$prev_conf_name"; save_state strategy.sha "$prev_conf_sha"
        rm -f "$prev_conf_backup"
        manage_service restart
        pause; return
    fi
    rm -f "$prev_conf_backup"

    local pct
    pct="$(awk -v a="$best_n" -v t="$total" 'BEGIN{ if (t>0) printf "%.1f", a*100/t; else print "0" }')"
    echo
    echo -e "\e[42m\e[30m  ИТОГ: лучшая стратегия — $best ($best_n из $total, $pct%)  ${C_RST}"
    echo
    echo -e "${C_CYN}Статистика:${C_RST}"
    local s n
    for s in "${stats[@]}"; do
        n="${s##*|}"
        printf "  %-34s %4s/%-4s %6s%%\n" "${s%|*}" "$n" "$total" \
            "$(awk -v a="$n" -v t="$total" 'BEGIN{ if (t>0) printf "%.1f", a*100/t; else print "0" }')"
    done
    echo
    msg "Применяю лучшую стратегию: $best"
    apply_strategy_by_name "$best" && manage_service restart
    pause
}
