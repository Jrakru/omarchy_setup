#!/bin/bash

detect_bootloader() {
    local bootloader=""
    
    if [ -f /etc/default/limine ]; then
        bootloader="limine"
    elif command -v grub-mkconfig &>/dev/null && [ -f /etc/default/grub ]; then
        bootloader="grub"
    elif bootctl status &>/dev/null 2>&1; then
        bootloader="systemd-boot"
    else
        bootloader="unknown"
    fi
    
    echo "$bootloader"
}

get_bootloader_config_file() {
    local bootloader="$1"
    
    case "$bootloader" in
        limine)
            echo "/etc/default/limine"
            ;;
        grub)
            echo "/etc/default/grub"
            ;;
        systemd-boot)
            echo "/boot/loader/entries/*.conf"
            ;;
        *)
            echo ""
            ;;
    esac
}

get_configure_script() {
    local bootloader="$1"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    case "$bootloader" in
        limine)
            echo "${script_dir}/configure-limine.sh"
            ;;
        grub)
            echo "${script_dir}/configure-grub.sh"
            ;;
        systemd-boot)
            echo "${script_dir}/configure-systemd-boot.sh"
            ;;
        *)
            echo ""
            ;;
    esac
}

check_resume_params() {
    local bootloader="$1"
    local config_file
    
    case "$bootloader" in
        limine)
            config_file="/etc/default/limine"
            if [ -f "$config_file" ]; then
                grep -q "resume=UUID=" "$config_file" && grep -q "resume_offset=" "$config_file"
                return $?
            fi
            return 1
            ;;
        grub)
            config_file="/etc/default/grub"
            if [ -f "$config_file" ]; then
                grep -q "resume=UUID=" "$config_file" && grep -q "resume_offset=" "$config_file"
                return $?
            fi
            return 1
            ;;
        systemd-boot)
            if [ -f /proc/cmdline ]; then
                grep -q "resume=UUID=" /proc/cmdline && grep -q "resume_offset=" /proc/cmdline
                return $?
            fi
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}
