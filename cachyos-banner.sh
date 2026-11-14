#!/usr/bin/env bash
# Bash startup banner; run from ~/.bashrc. Optional: CACHY_NAME, CACHY_DE, CACHY_WM.
# Battery options: CACHY_BATTERY_STYLE=pipe|block|square|heavy|ascii
# CACHY_BATTERY_LOW=20 overrides KDE low-battery detection; no system settings are changed.
# GPU readings depend on driver support. Missing readings are shown as N/A.
# Colors: cyan logo; load percentages green through 70%, red above 70%.

cachy_pct() {
    local value=$1 tint=''
    if [[ $value =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        if ((color)); then
            tint=$'\e[32m'
            awk -v p="$value" 'BEGIN {exit !(p>70)}' && tint=$'\e[31m'
        fi
        printf '%s(%s%%)%s' "$tint" "$value" "$reset"
    else printf '(N/A)'; fi
}

cachy_cpu_sample() {
    awk '/^cpu / {total=0; for(i=2;i<=9;i++) total+=$i; print total, $5+$6; exit}' /proc/stat
}

cachy_banner() {
    local color=0 reset='' bold=''
    if [[ ${1:-0} == 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]]; then
        color=1; reset=$'\e[0m'; bold=$'\e[1m'
    fi
    # Solid glyphs with a thin offset outline, inspired by the supplied logo.
    local -a logo=(
      ' ██████╗ █████╗  ██████╗██╗  ██╗██╗   ██╗ ██████╗ ███████╗'
      '██╔════╝██╔══██╗██╔════╝██║  ██║╚██╗ ██╔╝██╔═══██╗██╔════╝'
      '██║     ███████║██║     ███████║ ╚████╔╝ ██║   ██║███████╗'
      '██║     ██╔══██║██║     ██╔══██║  ╚██╔╝  ██║   ██║╚════██║'
      '╚██████╗██║  ██║╚██████╗██║  ██║   ██║   ╚██████╔╝███████║'
      ' ╚═════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚══════╝'
    )
    local -a shades=(159 153 117 81 75 67)
    local row cols=${COLUMNS:-80}
    [[ $cols =~ ^[0-9]+$ ]] || cols=80
    printf '\n'
    if ((cols < 60)); then
        ((color)) && printf '\033[38;5;117m'
        printf 'CachyOS%s\n' "$reset"
    else
        for row in "${!logo[@]}"; do
            ((color)) && printf '\033[38;5;%sm' "${shades[row]}"
            printf '%s%s\n' "${logo[row]}" "$reset"
        done
    fi
    printf '\n'
    local os kernel machine seconds days hours minutes up
    os=$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Linux}")
    kernel=$(uname -r)
    machine=$(hostname)
    read -r seconds _ < /proc/uptime
    seconds=${seconds%%.*}
    days=$((seconds / 86400)); hours=$((seconds / 3600 % 24)); minutes=$((seconds / 60 % 60))
    printf -v up '%dd %dh %dm' "$days" "$hours" "$minutes"
    printf 'OS:      %s\nKernel:  %s\nHost:    %s\nUptime:  %s\nShell:   Bash %s\n\n' \
        "$os" "$kernel" "$machine" "$up" "$BASH_VERSION"

    local de=${CACHY_DE:-${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-Unknown}}}
    local wm=${CACHY_WM:-} candidate
    if [[ -z $wm ]]; then
        if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then wm=Hyprland
        elif [[ -n ${SWAYSOCK:-} ]]; then wm=Sway
        elif [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && command -v pgrep >/dev/null 2>&1; then
            for candidate in kwin_wayland kwin_x11 Hyprland sway i3 bspwm awesome openbox xfwm4 marco mutter gnome-shell labwc niri wayfire; do
                if pgrep -u "$UID" -x "$candidate" >/dev/null 2>&1; then
                    wm=$candidate
                    [[ $wm == gnome-shell ]] && wm='Mutter (GNOME Shell)'
                    break
                fi
            done
        fi
    fi
    printf 'Desktop Environment: %s\nWindow Manager:      %s\n\n' "$de" "${wm:-Unknown / no graphical session}"


    local cpu_model cpu_clock a_total a_idle b_total b_idle cpu_pct cores busy
    cpu_model=$(awk -F ': *' '/model name|Hardware/ {print $2; exit}' /proc/cpuinfo)
    cpu_clock=$(awk -F ': *' '/cpu MHz/ {sum+=$2;n++} END {if(n) printf "%.0f MHz",sum/n; else print "N/A"}' /proc/cpuinfo)
    read -r a_total a_idle < <(cachy_cpu_sample)
    sleep 0.25
    read -r b_total b_idle < <(cachy_cpu_sample)
    cores=$(getconf _NPROCESSORS_ONLN)
    cpu_pct=$(awk -v t="$((b_total-a_total))" -v i="$((b_idle-a_idle))" 'BEGIN {if(t>0) printf "%.1f",100*(t-i)/t; else print "N/A"}')
    busy=$(awk -v p="$cpu_pct" -v n="$cores" 'BEGIN {if(p=="N/A") print "N/A"; else printf "%.2f / %d cores busy",p*n/100,n}')
    printf 'CPU:     %s | %s (average)\n' "${cpu_model:-Unknown}" "$cpu_clock"
    printf 'CPU load: %s ' "$busy"; cachy_pct "$cpu_pct"; printf '\n'

    local card device slot model vendor clock load found=0 nvidia_data='' line
    # Bound driver queries so a terminal does not wait indefinitely.
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia_data=$(timeout 2s nvidia-smi --query-gpu=pci.bus_id,name,clocks.current.graphics,utilization.gpu --format=csv,noheader,nounits 2>/dev/null)
    fi
    for card in /sys/class/drm/card[0-9]*; do
        [[ ${card##*/} =~ ^card[0-9]+$ && -d $card/device ]] || continue
        found=1; device=$card/device; slot=$(basename "$(readlink -f "$device")")
        vendor=$(cat "$device/vendor" 2>/dev/null)
        model='Unknown GPU'; clock='N/A'; load='N/A'
        if command -v lspci >/dev/null 2>&1; then
            model=$(lspci -s "$slot" 2>/dev/null | sed 's/^[^ ]* [^:]*: //')
        fi
        if [[ $vendor == 0x10de && -n $nvidia_data ]]; then
            line=$(awk -F ', *' -v s="$slot" 'tolower(substr($1,length($1)-11))==tolower(s) {print; exit}' <<< "$nvidia_data")
            if [[ -n $line ]]; then
                IFS=',' read -r _ model clock load <<< "$line"
                model=${model# }; clock=${clock// /}; load=${load// /}
                [[ $clock =~ ^[0-9]+$ ]] && clock="$clock MHz" || clock='N/A'
            fi
        else
            [[ -r $device/gpu_busy_percent ]] && read -r load < "$device/gpu_busy_percent"
            if [[ -r $device/pp_dpm_sclk ]]; then
                clock=$(awk '/\*/ {print $2; exit}' "$device/pp_dpm_sclk")
            else
                # Intel i915 / Xe: report clocks when exposed without privilege.
                local freq
                for freq in "$card/gt_cur_freq_mhz" "$card"/gt/gt*/rps_cur_freq_mhz "$device"/tile*/gt*/freq0/cur_freq; do
                    if [[ -r $freq ]]; then read -r clock < "$freq"; clock="$clock MHz"; break; fi
                done
            fi
        fi
        printf 'GPU:     %s | %s\n' "${model:-Unknown GPU}" "${clock:-N/A}"
        # GPU utilization is active time, not a fraction of the clock frequency.
        if [[ $load =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            printf 'GPU load: %s ms active / second ' "$(awk -v p="$load" 'BEGIN {printf "%.0f",p*10}')"
        else printf 'GPU load: unavailable '; fi
        cachy_pct "$load"; printf '\n'
    done
    ((found)) || printf 'GPU:     Not detected | clock N/A\nGPU load: unavailable (N/A)\n'

    local used total mem_pct
    read -r used total mem_pct < <(awk '/MemTotal:/ {t=$2} /MemAvailable:/ {a=$2} END {if(t) printf "%.2f %.2f %.1f\n",(t-a)/1048576,t/1048576,100*(t-a)/t}' /proc/meminfo)
    printf 'Memory:  %s / %s GiB ' "$used" "$total"; cachy_pct "$mem_pct"; printf '\n'

    local bat type capacity status now full units amount i filled red green batteries=0
    local low low_source threshold_value config_reader position tint_position
    local filled_char empty_char
    case ${CACHY_BATTERY_STYLE:-block} in
        block) filled_char='█'; empty_char='░' ;;
        square) filled_char='■'; empty_char='□' ;;
        heavy) filled_char='━'; empty_char='─' ;;
        ascii) filled_char='#'; empty_char='-' ;;
        *) filled_char='|'; empty_char='-' ;;
    esac
    for bat in /sys/class/power_supply/*; do
        [[ -r $bat/type ]] || continue
        read -r type < "$bat/type"; [[ $type == Battery ]] || continue
        batteries=1; capacity=''; status=Unknown; amount='capacity unavailable'
        [[ -r $bat/capacity ]] && read -r capacity < "$bat/capacity"
        [[ -r $bat/status ]] && read -r status < "$bat/status"
        for units in energy charge; do
            if [[ -r $bat/${units}_now && -r $bat/${units}_full ]]; then
                read -r now < "$bat/${units}_now"; read -r full < "$bat/${units}_full"
                amount=$(awk -v n="$now" -v f="$full" -v u="$units" 'BEGIN {printf "%.2f / %.2f %s",n/1e6,f/1e6,(u=="energy"?"Wh":"Ah")}')
                if [[ ! $capacity =~ ^[0-9]+$ && $full -gt 0 ]]; then capacity=$((100*now/full)); fi
                break
            fi
        done
        # KDE uses BatteryManagement/BatteryLowLevel for its Low Battery state.
        low=10; low_source='fallback 10%'
        threshold_value=''
        for config_reader in kreadconfig6 kreadconfig5; do
            if command -v "$config_reader" >/dev/null 2>&1; then
                threshold_value=$("$config_reader" --file powerdevilrc --group BatteryManagement --key BatteryLowLevel --default 10 2>/dev/null)
                low_source='KDE setting/default'
                break
            fi
        done
        if [[ -z $threshold_value && -r ${XDG_CONFIG_HOME:-$HOME/.config}/powerdevilrc ]]; then
            threshold_value=$(awk '
                /^\[BatteryManagement\]$/ {group=1; next}
                /^\[/ {group=0}
                group && /^BatteryLowLevel[[:space:]]*=/ {
                    sub(/^[^=]*=/, ""); gsub(/[[:space:]]/, ""); value=$0
                }
                END {print value}
            ' "${XDG_CONFIG_HOME:-$HOME/.config}/powerdevilrc")
            low_source='KDE setting'
        fi
        if [[ $threshold_value =~ ^[0-9]{1,2}$ ]] && ((10#$threshold_value >= 1)); then
            low=$((10#$threshold_value)); low_source="$low_source ${low}%"
        else
            low=10; low_source='fallback 10%'
        fi
        threshold_value=${CACHY_BATTERY_LOW:-}
        if [[ $threshold_value =~ ^[0-9]{1,2}$ ]] && ((10#$threshold_value >= 1)); then
            low=$((10#$threshold_value)); low_source="manual ${low}%"
        fi
        printf 'Battery %s: %s | %s | Low threshold: %s\n  ' "${bat##*/}" "$amount" "$status" "$low_source"
        if [[ $capacity =~ ^[0-9]+$ ]]; then
            ((capacity > 100)) && capacity=100
            filled=$(((capacity*30+50)/100))
            for ((i=0;i<30;i++)); do
                if ((i < filled)); then
                    # Keep fill on an honest 0..100% scale; only rescale colors.
                    # Red at/below the low-battery threshold; green at 100%.
                    position=$(((i+1)*100/30))
                    tint_position=$(((position-low)*100/(100-low)))
                    ((tint_position < 0)) && tint_position=0
                    ((tint_position > 100)) && tint_position=100
                    if ((tint_position <= 50)); then
                        red=220; green=$((60+140*tint_position/50))
                    else
                        red=$((220-180*(tint_position-50)/50)); green=200
                    fi
                    ((color)) && printf '\033[38;2;%s;%s;90m' "$red" "$green"
                    printf '%s' "$filled_char"
                else
                    ((color)) && printf '\033[38;5;240m'
                    printf '%s' "$empty_char"
                fi
            done
            printf '%s ' "$reset"; cachy_pct "$capacity"; printf '\n'
        else printf '(N/A)\n'; fi
    done
    ((batteries)) || printf 'Battery: Not present\n'
    printf '\n'

    local name=${CACHY_NAME:-${USER:-$(id -un)}} hour day today clock period
    # Read all date fields together so they describe the same instant.
    IFS='|' read -r hour day today clock < <(LC_TIME=C date '+%H|%A|%d/%m/%Y|%I:%M %p')
    hour=$((10#$hour))
    if ((hour >= 5 && hour < 12)); then period=Morning
    elif ((hour >= 12 && hour < 17)); then period=Afternoon
    elif ((hour >= 17 && hour < 22)); then period=Evening
    else period=Night
    fi
    printf '%sGreetings and Good %s, %s!%s\nToday is %s the %s, and it is %s.\n\n' \
        "$bold" "$period" "$name" "$reset" "$day" "$today" "$clock"
}

# Capture with explicit color intent so framing does not disable terminal colors.
cachy_frame() {
    local terminal_cols=${COLUMNS:-} use_color=0
    [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]] && use_color=1
    if [[ ! $terminal_cols =~ ^[0-9]+$ ]]; then
        terminal_cols=$(tput cols 2>/dev/null) || terminal_cols=80
    fi
    [[ $terminal_cols =~ ^[0-9]+$ ]] || terminal_cols=80
    ((terminal_cols > 110)) && terminal_cols=110
    ((terminal_cols < 10)) && terminal_cols=10
    local width=$((terminal_cols-5)) border='' n line rest token segment count active
    local sgr=$'\e''\[[0-9;]*m' reset=''
    ((use_color)) && reset=$'\e[0m'
    for ((n=0;n<width+2;n++)); do border+='━'; done
    printf '┏%s┓\n' "$border"
    while IFS= read -r line; do
        rest=$line; segment=''; count=0; active=''
        while [[ -n $rest ]]; do
            if [[ $rest =~ ^($sgr) ]]; then
                token=${BASH_REMATCH[1]}
                segment+=$token; active+=$token
                rest=${rest:${#token}}
            else
                if ((count == width)); then
                    printf '┃ %s%s ┃\n' "$segment" "$reset"
                    segment=$active; count=0
                fi
                segment+=${rest:0:1}; rest=${rest:1}; ((count+=1))
            fi
        done
        printf '┃ %s%s%*s ┃\n' "$segment" "$reset" "$((width-count))" ''
    done < <(COLUMNS=$width cachy_banner "$use_color")
    printf '┗%s┛\n' "$border"
}

cachy_frame
unset -f cachy_banner cachy_pct cachy_cpu_sample cachy_frame
