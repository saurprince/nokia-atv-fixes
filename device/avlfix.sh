#!/system/bin/sh
# Runs on the Nokia TV (as the adb shell user). The firmware keeps "Auto Volume = Auto" in the
# menu after standby but stops applying it; flipping it Off -> Auto re-applies it. This script
# waits for the TV to wake up and does that flip through the menu, checking the screen before
# every OK press so it can never select anything else (the same screen has a Reset tab).
#
#   sh avlfix.sh          watch for wake-ups forever (started in the background by avl-autofix.ps1)
#   sh avlfix.sh once     do the flip right now, then exit
#
# Menu path: Sound adjustments (row 3 "Advanced Setting") -> Advanced Setting, right-hand list
# (row 1 of 5 "Auto Volume") -> choices (button 1 "Auto", button 2 "Off").

umask 077   # files created here (log, screen dumps) are private to the adb shell user
DIR=/data/local/tmp
LOG=$DIR/avlfix.log
TOP=$DIR/avlfix-top.txt
UI=$DIR/avlfix-ui.xml
MENU=com.realtek.tv.actionmenu

log() {
    [ -f $LOG ] && [ $(wc -c < $LOG) -gt 100000 ] && tail -n 200 $LOG > $LOG.tmp && mv $LOG.tmp $LOG
    echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG
}

wakefulness() { dumpsys power | sed -n 's/^ *mWakefulness=\([A-Za-z]*\).*/\1/p' | head -n 1; }
menu_open() { dumpsys window | grep -m 1 mCurrentFocus | grep -q $MENU; }
# Each `input` call takes ~1.3 s on this TV no matter how many keys it sends, so keys are batched
# wherever the next press can only land on Auto or Off.
key() { input keyevent "$@"; sleep 0.2; }

# The menu app and the TV's sound service log what they do; used as fast, exact confirmation.
log_since_start() { logcat -d -T "$STARTED_AT" -s AdvancedAutoVolumeFragment:D CAQControl:D 2>/dev/null; }
logged() {
    t=0
    while [ $t -lt 6 ]; do
        log_since_start | grep -q "$1" && return 0
        sleep 0.5; t=$((t + 1))
    done
    return 1
}

# Fast view dump (~0.3 s) of the sound menu only.
snap() { dumpsys activity top | sed -n -E "/ACTIVITY $MENU\//,/^ *(TASK|ACTIVITY) /p" > $TOP; }

# Second flag group of every view with this id, e.g. "..S....." (S = highlighted, .F = has focus).
flags() { grep -E "app:id/$1( aid=[0-9]+)?\}" $TOP | sed -E 's/.*\{[0-9a-f]+ [^ ]+ ([^ ]+) .*/\1/'; }

# "<highlighted row> <row count>" for views with this id, e.g. "3 3"; 0 = nothing highlighted.
pos() {
    i=0; p=0
    for f in $(flags $1); do
        i=$((i + 1))
        case "$f" in ??S*) p=$i ;; esac
    done
    echo "$p $i"
}

has_focus() { flags $1 | grep -q '^.F'; }

# expect <list id> <row id> "<pos> <count>": waits up to ~3 s for the screen to match.
expect() {
    t=0
    while [ $t -lt 6 ]; do
        snap
        if has_focus $1 && [ "$(pos $2)" = "$3" ]; then return 0; fi
        sleep 0.5; t=$((t + 1))
    done
    log "stopped: expected $2 row '$3' in $1, screen shows '$(pos $2)'"
    return 1
}

# One slower text check that the choices really are "Auto Volume: Auto / Off".
choices_are_auto_volume() {
    uiautomator dump $UI > /dev/null 2>&1
    grep -q 'text="Auto Volume"' $UI && grep -q 'text="Auto" resource-id="[^"]*bt_textview_button_listview_item"' $UI \
        && grep -q 'text="Off" resource-id="[^"]*bt_textview_button_listview_item"' $UI
}

leave_menu() {
    i=0
    while [ $i -lt 4 ] && menu_open; do key BACK; i=$((i + 1)); done
}

flip() {
    STARTED_AT=$(date '+%m-%d %H:%M:%S.000')
    am start -a $MENU.sound.SoundAdjustAction > /dev/null 2>&1
    sleep 1.5
    menu_open || { log "stopped: sound menu did not open"; return 1; }

    # Sound adjustments: the menu opens on row 1; "Advanced Setting" is row 3 of 3. Right after
    # start-up or wake the TV can drop key presses, so wait for the list and retry until row 3.
    t=0; while [ $t -lt 8 ]; do snap; has_focus lv_input_cannels_info_setting && break; sleep 0.5; t=$((t + 1)); done
    n=0
    while [ $n -lt 4 ]; do
        snap
        case "$(pos info_title)" in
            "3 3") break ;;
            "1 3") key DPAD_DOWN DPAD_DOWN ;;
            "2 3") key DPAD_DOWN ;;
            *) sleep 0.5 ;;
        esac
        n=$((n + 1))
    done
    expect lv_input_cannels_info_setting info_title "3 3" || return 1
    key DPAD_CENTER

    # Advanced Setting: focus starts on the left tabs (Volume Setting / Sound Mode Related / Reset).
    # RIGHT moves into the Volume Setting list, whose row 1 is Auto Volume; OK opens its choices.
    t=0; while [ $t -lt 6 ]; do snap; has_focus lv_advanced_settings_choose && break; sleep 0.5; t=$((t + 1)); done
    has_focus lv_advanced_settings_choose || { log "stopped: Advanced Setting did not open"; return 1; }
    key DPAD_RIGHT DPAD_CENTER

    # Choices open on the current value: button 1 = Auto, button 2 = Off
    t=0; while [ $t -lt 6 ]; do snap; has_focus lv_textview_button_listview && break; sleep 0.5; t=$((t + 1)); done
    case "$(pos bt_textview_button_listview_item)" in
        "2 2") log "Auto Volume is set to Off in the menu - leaving it alone"; return 0 ;;
        "1 2") ;;
        *) log "stopped: Auto Volume choices not recognised"; return 1 ;;
    esac
    logged "AdvancedAutoVolumeFragment" || choices_are_auto_volume \
        || { log "stopped: the open choices are not Auto Volume"; return 1; }

    # From here on Auto Volume is briefly Off, so only a screen mismatch may stop the script.
    key DPAD_DOWN DPAD_CENTER                         # Auto -> Off
    expect lv_advanced_settings_choose_common advanced_settings_choose_common_title "1 5" \
        || { log "WARNING: Auto Volume may be left Off - please check the menu"; return 1; }
    key DPAD_CENTER                                   # reopen choices (now on Off)
    expect lv_textview_button_listview bt_textview_button_listview_item "2 2" \
        || { log "WARNING: Auto Volume may be left Off - please check the menu"; return 1; }
    key DPAD_UP DPAD_CENTER                           # Off -> Auto (re-applied)
    logged "setAutoVolume:Off" || log "note: no Off line in the TV log (screen checks passed)"
    if logged "setAutoVolume:On"; then
        log "Auto Volume re-applied (Off -> Auto, confirmed by the TV's sound service)"
    elif expect lv_advanced_settings_choose_common advanced_settings_choose_common_title "1 5"; then
        log "Auto Volume re-applied (Off -> Auto; screen checks passed, no TV log line)"
    else
        log "WARNING: could not confirm Auto Volume is back on - please check the menu"
        return 1
    fi
}

run_flip() {
    started=$(date +%s)
    flip
    leave_menu
    log "menu closed after $(( $(date +%s) - started ))s"
}

if [ "$1" = "once" ]; then
    run_flip
    exit 0
fi

echo $$ > $DIR/avlfix.pid
log "watcher started (pid $$)"
prev=$(wakefulness)
last=$(date +%s)
while true; do
    sleep 3
    now=$(date +%s)
    gap=$((now - last))
    w=$(wakefulness)
    if [ "$w" != "$prev" ]; then log "power state $prev -> $w"; fi
    # Wake-up = Asleep -> Awake, or the CPU was suspended (3 s sleep took far longer).
    if [ "$w" = "Awake" ] && { [ "$prev" = "Asleep" ] || [ $gap -gt 30 ]; }; then
        log "wake-up detected (was $prev, loop gap ${gap}s)"
        sleep 6
        run_flip
        now=$(date +%s)
    fi
    prev=$w
    last=$now
done
