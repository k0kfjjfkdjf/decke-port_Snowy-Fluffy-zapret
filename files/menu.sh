#!/bin/bash

credits() {
    echo
    echo -e "\e[1;96mОригинал\e[0m by: \e[4;94mhttps://t.me/linux_hi\e[0m  ·  \e[1;96mпорт для Steam Deck\e[0m"
    echo
}

header() {
    local title="$1" width=46 pad
    pad=$(( (width - ${#title}) / 2 ))
    echo -e "${C_CYN}╔$(printf '═%.0s' $(seq 1 $width))╗"
    printf "║%*s%s%*s║\n" "$pad" "" "$title" "$((width - pad - ${#title}))" ""
    echo -e "╚$(printf '═%.0s' $(seq 1 $width))╝${C_RST}"
}

main_menu() {
    while true; do
        clear
        check_zapret_exist
        check_zapret_status
        repair_unit_if_needed
        detect_fwtype
        clear
        header "Меню управления Запретом"

        if [[ $ZAPRET_EXIST == true ]]; then
            [[ $ZAPRET_ACTIVE == true ]] && echo -e "  ${C_GRN}Запрет запущен${C_RST}" || echo -e "  ${C_RED}Запрет выключен${C_RST}"
            [[ $ZAPRET_ENABLED == true ]] && echo -e "  ${C_GRN}Запрет в автозагрузке${C_RST}" || echo -e "  ${C_YEL}Запрет не в автозагрузке${C_RST}"
            if nfqws_running; then
                echo -e "  nfqws: ${C_GRN}работает${C_RST} (PID $NFQWS_PIDS)"
            else
                echo -e "  nfqws: ${C_RED}не запущен${C_RST}"
            fi
            echo -e "  Файрвол: $(fw_status_text)"
            [[ -z $FWTYPE ]] && echo -e "  ${C_YEL}Похоже, nftables пропал после обновления SteamOS — пункт 5.${C_RST}"
            echo
            echo -e "  ${C_BLU}0)${C_RST} Выйти"
            echo -e "  ${C_YEL}1)${C_RST} Проверить на обновления и обновить"
            echo -e "  ${C_CYN}2)${C_RST} Сменить конфигурацию запрета"
            echo -e "  ${C_MAG}3)${C_RST} Управление сервисом запрета"
            echo -e "  ${C_RED}4)${C_RST} Удалить Запрет"
            echo -e "  ${C_GRN}5)${C_RST} Восстановить nftables (после обновления SteamOS)"
            credits
            read -rp $'\e[1;36mВыберите действие: \e[0m' CHOICE
            case "$CHOICE" in
                1) update_zapret_menu ;;
                2) change_configuration ;;
                3) toggle_service ;;
                4) uninstall_zapret ;;
                5) if fw_repair_any; then set_config_fwtype; manage_service restart; fi; pause ;;
                0) $TPUT_E; exit 0 ;;
                *) echo -e "${C_RED}Неверный ввод! Попробуйте снова.${C_RST}"; sleep 2 ;;
            esac
        else
            echo -e "  ${C_YEL}Запрет не установлен в $ZBASE${C_RST}"
            if [[ -d $ZBASE/zapret ]]; then
                echo -e "  ${C_YEL}Не хватает:${C_RST}"
                local m
                for m in "${MISSING[@]}"; do echo "    - $m"; done
            fi
            if nfqws_running; then
                echo -e "  ${C_YEL}При этом nfqws запущен (PID $NFQWS_PIDS) — это другая установка zapret.${C_RST}"
            fi
            legacy_install_hint
            echo -e "  Файрвол: $(fw_status_text)"
            echo
            echo -e "  ${C_BLU}0)${C_RST} Выйти"
            echo -e "  ${C_GRN}1)${C_RST} Установить Запрет (в $ZBASE)"
            echo -e "  ${C_CYN}2)${C_RST} Проверить скрипт на обновления"
            credits
            read -rp $'\e[1;36mВыберите действие: \e[0m' CHOICE
            case "$CHOICE" in
                1) install_zapret ;;
                2) update_installed_script ;;
                0) $TPUT_E; exit 0 ;;
                *) echo -e "${C_RED}Неверный ввод! Попробуйте снова.${C_RST}"; sleep 2 ;;
            esac
        fi
    done
}

# Пункт 5: переставить nftables, даже если что-то из файрвола ещё есть
fw_repair_any() {
    if exists nft; then
        ok "nft на месте, восстанавливать нечего."
        return 0
    fi
    if ask_yn "Установить nftables через pacman?" Y; then
        pacman_install nftables && detect_fwtype && [[ -n $FWTYPE ]]
    else
        return 1
    fi
}

change_configuration() {
    while true; do
        clear
        cur_conf; cur_list; game_mode_check
        header "Управление конфигурацией Запрета"
        echo -e "  ${C_YEL}Используемая стратегия:${C_RST} ${C_GRN}$cr_cnf${C_RST}"
        echo -e "  ${C_YEL}Используемый хостлист:${C_RST} ${C_GRN}$cr_lst${C_RST}"
        echo -e "  ${C_YEL}Игровой режим:${C_RST} ${C_GRN}$game_mode_status${C_RST}"
        echo
        echo -e "  ${C_RED}0)${C_RST} Выйти в меню"
        if [[ $game_mode_status == "включен" ]]; then
            echo -e "  ${C_BLU}1)${C_RST} Выключить игровой режим"
        else
            echo -e "  ${C_BLU}1)${C_RST} Включить игровой режим"
        fi
        echo -e "  ${C_BLU}2)${C_RST} Сменить стратегию"
        echo -e "  ${C_BLU}3)${C_RST} Сменить лист обхода"
        echo -e "  ${C_BLU}4)${C_RST} Добавить IP или домены в лист"
        echo -e "  ${C_BLU}5)${C_RST} Удалить IP или домены из листа"
        echo -e "  ${C_BLU}6)${C_RST} Найти IP или домены в листе"
        echo -e "  ${C_BLU}7)${C_RST} Добавить IP или домены в лист исключений (exclude)"
        echo -e "  ${C_BLU}8)${C_RST} Удалить IP или домены из листа исключений (exclude)"
        echo -e "  ${C_BLU}9)${C_RST} Найти IP или домены в листе исключений (exclude)"
        echo -e "  ${C_BLU}10)${C_RST} Установить стратегию из файла (путь)"
        echo -e "  ${C_BLU}11)${C_RST} Установить хостлист из файла (путь)"
        echo -e "  ${C_BLU}12)${C_RST} Редактировать стратегию напрямую"
        echo -e "  ${C_BLU}13)${C_RST} Редактировать хостлист напрямую"
        echo -e "  ${C_BLU}14)${C_RST} Редактировать хостлист исключений (exclude) напрямую"
        echo -e "  ${C_BLU}15)${C_RST} Создать/Редактировать кастомный хостлист"
        echo -e "  ${C_BLU}16)${C_RST} Создать/Редактировать кастомную стратегию"
        credits
        read -rp $'\e[1;36mВыберите действие: \e[0m' CHOICE
        case "$CHOICE" in
            1) toggle_game_mode ;;
            2) configure_zapret_menu ;;
            3) configure_zapret_list ;;
            4) add_to_list "$HOSTS_USER" "лист" ;;
            5) delete_from_list "$HOSTS_USER" "листа" ;;
            6) search_in_list "$HOSTS_USER" ;;
            7) add_to_list "$HOSTS_EXCLUDE" "лист исключений" ;;
            8) delete_from_list "$HOSTS_EXCLUDE" "листа исключений" ;;
            9) search_in_list "$HOSTS_EXCLUDE" ;;
            10) configure_custom_conf_path ;;
            11) configure_custom_list_path ;;
            12) edit_and_restart "$ZAPRET_CONFIG" ;;
            13) edit_and_restart "$HOSTS_USER" ;;
            14) edit_and_restart "$HOSTS_EXCLUDE" ;;
            15) edit_cust_list ;;
            16) edit_cust_conf ;;
            0) return ;;
            *) echo -e "${C_RED}Неверный ввод! Попробуйте снова.${C_RST}"; sleep 2 ;;
        esac
    done
}

configure_zapret_menu() {
    while true; do
        clear
        cur_conf
        header "Управление стратегиями Запрета"
        echo -e "  ${C_YEL}Используемая стратегия:${C_RST} ${C_GRN}$cr_cnf${C_RST}"
        echo -e "  ${C_RED}0)${C_RST} Выйти в меню"
        echo -e "  ${C_BLU}1)${C_RST} Выбрать стратегию вручную"
        echo -e "  ${C_BLU}2)${C_RST} Подобрать стратегию автоматически"
        credits
        read -rp $'\e[1;36mВыберите действие: \e[0m' CHOICE
        case "$CHOICE" in
            1) configure_zapret_conf ;;
            2) check_conf ;;
            0) return ;;
            *) echo -e "${C_RED}Неверный ввод! Попробуйте снова.${C_RST}"; sleep 2 ;;
        esac
    done
}

update_zapret_menu() {
    while true; do
        clear
        header "Обновление Запрета"
        echo -e "  Текущая версия:   ${C_GRN}$(current_version)${C_RST}"
        echo -e "  Последняя версия: ${C_GRN}$(get_latest_version)${C_RST}"
        echo
        echo -e "  ${C_RED}0)${C_RST} Выйти в меню"
        echo -e "  ${C_YEL}1)${C_RST} Обновить ${C_YEL}всё${C_RST} (zapret, стратегии, скрипт) — твои списки сохранятся"
        echo -e "  ${C_GRN}2)${C_RST} Обновить только ${C_GRN}скрипт${C_RST}"
        credits
        read -rp $'\e[1;36mВыберите действие: \e[0m' CHOICE
        case "$CHOICE" in
            1) update_zapret ;;
            2) update_installed_script ;;
            0) return ;;
            *) echo -e "${C_RED}Неверный ввод! Попробуйте снова.${C_RST}"; sleep 2 ;;
        esac
    done
}
