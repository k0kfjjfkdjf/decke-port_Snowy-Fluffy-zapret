#!/bin/bash
# Установка, обновление и удаление.

get_latest_version() {
    if [[ -z ${rver:-} ]]; then
        rver="$(curl -fsS --max-time 10 "https://api.github.com/repos/$ZAPRET_SLUG/releases/latest" 2>/dev/null \
                | grep -m1 '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')"
    fi
    if [[ -z $rver ]]; then
        # запасной путь без API: смотрим, куда редиректит /releases/latest
        rver="$(curl -fsSI --max-time 10 "https://github.com/$ZAPRET_SLUG/releases/latest" 2>/dev/null \
                | grep -i '^location:' | grep -o 'tag/v[0-9.]*' | cut -d/ -f2 | sed 's/^v//')"
    fi
    echo "${rver:-неизвестно}"
}

current_version() {
    [[ -f $VER_FILE ]] && cat "$VER_FILE" || echo "неизвестно"
}

# Скачать релиз во временный каталог, проверить и только потом заменить ZAPRET_DIR
download_zapret_release() {
    local ver tmp dir url
    ver="$(get_latest_version)"
    [[ $ver == неизвестно ]] && { err "Не удалось узнать последнюю версию zapret. Проверьте сеть."; return 1; }
    url="https://github.com/$ZAPRET_SLUG/releases/download/v$ver/zapret-v$ver.tar.gz"
    tmp="$(mk_tmp)" || return 1
    msg "Скачиваю zapret v$ver..."
    if ! curl -fL --retry 3 --max-time 300 -o "$tmp/z.tgz" "$url"; then
        rm -rf "$tmp"; err "Не удалось скачать релиз: $url"; return 1
    fi
    if ! tar -xzf "$tmp/z.tgz" -C "$tmp"; then
        rm -rf "$tmp"; err "Не удалось распаковать релиз."; return 1
    fi
    dir="$tmp/zapret-v$ver"
    if [[ ! -d $dir/binaries || ! -f $dir/init.d/sysv/zapret ]]; then
        rm -rf "$tmp"; err "В архиве нет ожидаемых файлов (binaries, init.d)."; return 1
    fi
    rm -rf "$ZAPRET_DIR"
    mv "$dir" "$ZAPRET_DIR"
    rm -rf "$tmp"
    echo "$ver" > "$VER_FILE"
}

fetch_cfgs() {
    msg "Загружаю стратегии и списки ($CFGS_SLUG)..."
    fetch_repo "$CFGS_SLUG" "$CFGS_BRANCH" "$CFGS_DIR" || { err "Не удалось загрузить $CFGS_SLUG"; return 1; }
}

fetch_installer() {
    msg "Загружаю скрипт управления ($INSTALLER_SLUG)..."
    fetch_repo "$INSTALLER_SLUG" "$INSTALLER_BRANCH" "$INSTALLER_DIR" || { err "Не удалось загрузить $INSTALLER_SLUG"; return 1; }
    chmod +x "$INSTALLER_DIR/zapret-control.sh" "$INSTALLER_DIR/installer.sh" 2>/dev/null
    return 0
}

run_install_bin() {
    msg "Подбираю бинарники под архитектуру..."
    ( cd "$ZAPRET_DIR" && sh ./install_bin.sh ) >/dev/null 2>&1
    if [[ ! -x $ZAPRET_DIR/nfq/nfqws ]]; then
        err "install_bin.sh не смог подобрать бинарники (nfq/nfqws не найден)."
        return 1
    fi
}

# Файлы, которые не входят в релиз и должны появиться после установки.
# force=1 — перезаписать списки значениями по умолчанию.
deploy_defaults() {
    local force="${1:-0}"
    mkdir -p "$FAKE_DIR" "$IPSET_DIR" "$CUSTOM_DIR" "$STATE_DIR"
    cp -f "$CFGS_DIR"/bin/* "$FAKE_DIR"/ 2>/dev/null || warn "Не удалось скопировать fake-файлы"
    [[ -f $HOSTS_EXCLUDE ]] || touch "$HOSTS_EXCLUDE"
    [[ -f $IPSET_GAME ]] || echo "203.0.113.77" > "$IPSET_GAME"
    if (( force )) || [[ ! -f $IPSET_DISCORD ]]; then
        cp -f "$CFGS_DIR/lists/ipset-discord.txt" "$IPSET_DISCORD" 2>/dev/null || touch "$IPSET_DISCORD"
    fi
    if (( force )) || [[ ! -f $HOSTS_USER ]]; then
        apply_list_by_name list-basic.txt || touch "$HOSTS_USER"
    fi
}

fix_permissions() {
    chown -R root:root "$ZBASE"
    chmod 755 "$ZBASE"
    find "$ZBASE" -path "$ZBASE/.tmp.*" -prune -o -type d -exec chmod a+rx {} + 2>/dev/null
    find "$ZBASE" -path "$ZBASE/.tmp.*" -prune -o -type f -exec chmod a+r {} + 2>/dev/null
}

# Команда zapret и ярлык в меню приложений (десктопный режим Деки)
install_launcher() {
    local bindir="$TARGET_HOME/.local/bin" appdir="$TARGET_HOME/.local/share/applications"
    local term_exec rc="$TARGET_HOME/.bashrc"
    sudo -u "$TARGET_USER" mkdir -p "$bindir" "$appdir" 2>/dev/null || mkdir -p "$bindir" "$appdir"
    ln -sfn "$INSTALLER_DIR/zapret-control.sh" "$bindir/zapret"
    chown -h "$TARGET_USER": "$bindir/zapret" 2>/dev/null

    if [[ -f $rc ]] && ! grep -q '\.local/bin' "$rc"; then
        printf '\n# zapret (Steam Deck port)\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
    fi

    if exists konsole; then
        term_exec="konsole -e $INSTALLER_DIR/zapret-control.sh"
    else
        term_exec="$INSTALLER_DIR/zapret-control.sh"
    fi
    cat > "$appdir/zapret.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Zapret
Comment=Управление zapret (обход DPI)
Exec=$term_exec
Icon=network-vpn
Terminal=$(exists konsole && echo false || echo true)
Categories=Network;System;
EOF
    chown "$TARGET_USER": "$appdir/zapret.desktop" 2>/dev/null
}

remove_launcher() {
    rm -f "$TARGET_HOME/.local/bin/zapret" "$TARGET_HOME/.local/share/applications/zapret.desktop"
}

install_zapret() {
    clear
    msg "Установка zapret в $ZBASE"
    detect_fwtype
    if [[ -z $FWTYPE ]]; then
        fw_repair || { err "Без nft или iptables zapret работать не будет."; pause; return 1; }
    fi
    ok "Файрвол: $FWTYPE"
    check_kernel_modules

    systemctl stop "$UNIT_NAME" >/dev/null 2>&1
    cleanup_legacy_units

    mkdir -p "$ZBASE" && chmod 755 "$ZBASE"
    download_zapret_release || { pause; return 1; }
    fetch_cfgs || { pause; return 1; }
    [[ -f $INSTALLER_DIR/zapret-control.sh ]] || fetch_installer || { pause; return 1; }
    run_install_bin || { pause; return 1; }

    deploy_defaults 1
    apply_strategy_by_name general || warn "Стратегия general не найдена, выберите стратегию в меню."
    fix_permissions

    msg "Создаю сервис $UNIT_FILE..."
    write_unit
    manage_autostart enable
    manage_service restart

    install_launcher
    echo
    ok "Zapret установлен. Команда для меню: ${C_GRN}zapret${C_RST} (в новом терминале), или ярлык «Zapret» в меню приложений."
    echo
    if ask_yn "Выбрать стратегию сейчас? (по умолчанию стоит general)" Y; then
        configure_zapret_menu
    fi
}

# После обновления релиза вернуть свои списки/конфиг
preserve_user_files() {
    local b="$1" f
    for f in "$ZAPRET_CONFIG" "$HOSTS_USER" "$HOSTS_EXCLUDE" "$IPSET_GAME" "$IPSET_DISCORD"; do
        [[ -f $f ]] && cp -p "$f" "$b/$(basename "$f")"
    done
}

restore_user_files() {
    local b="$1" f
    mkdir -p "$IPSET_DIR"
    [[ -f $b/config ]] && cp -p "$b/config" "$ZAPRET_CONFIG"
    for f in zapret-hosts-user.txt zapret-hosts-user-exclude.txt ipset-game.txt ipset-discord.txt; do
        [[ -f $b/$f ]] && cp -p "$b/$f" "$IPSET_DIR/$f"
    done
}

update_zapret() {
    local cur latest b name
    clear
    cur="$(current_version)"; latest="$(get_latest_version)"
    if [[ $cur == "$latest" && $latest != неизвестно ]]; then
        echo "Установлена актуальная версия zapret ($cur)."
        ask_yn "Всё равно переустановить zapret и обновить стратегии?" N || { update_installed_script; return; }
    fi

    b="$(mk_tmp)" || { pause; return; }
    preserve_user_files "$b"
    manage_service stop >/dev/null 2>&1

    if download_zapret_release && run_install_bin; then
        restore_user_files "$b"
        ok "zapret обновлён до $(current_version)"
    else
        err "Обновление zapret не удалось."
        restore_user_files "$b"
    fi
    rm -rf "$b"

    if fetch_cfgs; then
        deploy_defaults 0
        # стратегию из репозитория переприменяем, только если ты её не правил руками
        name="$(read_state strategy)"
        if [[ -n $name && $(read_state strategy.sha) == "$(file_sha "$ZAPRET_CONFIG")" ]] \
           && { [[ -f $CFGS_DIR/configurations/$name ]] || [[ $name == conf-custom ]]; }; then
            apply_strategy_by_name "$name" && ok "Стратегия '$name' обновлена из репозитория."
        fi
    fi
    set_config_fwtype
    fix_permissions
    write_unit
    manage_service restart

    update_installed_script
}

update_installed_script() {
    fetch_installer || { pause; return; }
    fix_permissions
    install_launcher
    ok "Скрипт управления обновлён."
    pause
    exec bash "$INSTALLER_DIR/zapret-control.sh"
}

uninstall_zapret() {
    ask_yn "Вы действительно хотите удалить zapret (весь каталог $ZBASE)?" N || return
    systemctl stop "$UNIT_NAME" >/dev/null 2>&1
    systemctl disable "$UNIT_NAME" >/dev/null 2>&1
    rm -f "$UNIT_FILE"
    systemctl daemon-reload
    remove_launcher
    rm -rf "$ZBASE"
    ok "Zapret удалён."
    $TPUT_E
    exit 0
}
