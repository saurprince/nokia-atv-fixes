#!/usr/bin/env bash
# fixes.sh - install / check / run / remove the Auto Volume + Netflix-button fixes. No AI needed.
# Works on Linux, macOS, Git Bash on Windows, and Termux on an Android phone (needs the "adb" tool).
# The fixes are one small Android app (local.avlfix) plus a helper script that lives on the TV.
#
#   bash scripts/fixes.sh <tv-ip> status                       is the app installed, is the script safe, last result
#   bash scripts/fixes.sh <tv-ip> install [--apk FILE] [--script-only]
#                                                              install the APK, copy the script, turn the watcher on
#   bash scripts/fixes.sh <tv-ip> run                          re-apply Auto Volume now (sound menu visible ~20-30 s)
#   bash scripts/fixes.sh <tv-ip> remove                       turn the watcher off, uninstall, delete script and logs
#
# --apk FILE      APK to install (default: app/avlfix.apk - build it first, see README.md)
# --script-only   with "install": only update the on-TV script and its permissions, keep the installed app
set -u
export MSYS_NO_PATHCONV=1   # Git Bash on Windows must not rewrite /data/... style arguments
here="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<'EOF'
Usage: bash scripts/fixes.sh <tv-ip> status|install|run|remove [--apk FILE] [--script-only]
EOF
  exit 1
}

[ $# -ge 2 ] || usage
tv_ip=$1; action=$2; shift 2
case $action in status|install|run|remove) ;; *) usage ;; esac
apk="$here/../app/avlfix.apk"; script_only=0
while [ $# -gt 0 ]; do
  case $1 in
    --apk)         [ $# -ge 2 ] || usage; apk=$2; shift 2 ;;
    --script-only) script_only=1; shift ;;
    *)             usage ;;
  esac
done

component="local.avlfix/local.avlfix.NetflixKeyService"
remote_script=/data/local/tmp/avlfix.sh
app_log=/sdcard/Android/data/local.avlfix/files/avlfix.log
local_script="$here/../device/avlfix.sh"

adb_bin=${ADB:-adb}
command -v "$adb_bin" >/dev/null 2>&1 || {
  echo "adb not found. Install Android platform-tools, put adb on your PATH, or set ADB=/full/path/to/adb."; exit 1; }
case $tv_ip in *:*) dev=$tv_ip ;; *) dev=$tv_ip:5555 ;; esac
out=$("$adb_bin" connect "$dev" 2>&1)
case $out in
  *"connected to"*|*"already connected"*) ;;
  *) echo "Could not connect to $dev: $out"
     echo "Check the TV's IP address, that both are on the same network, that USB debugging is on,"
     echo "and accept the 'Allow USB debugging?' prompt on the TV if it appears."; exit 1 ;;
esac
state=$("$adb_bin" -s "$dev" get-state 2>&1 | tr -d '\r')
[ "$state" = device ] || {
  echo "The TV reports '$state'. Accept the 'Allow USB debugging?' prompt on the TV (tick 'Always allow'), then run this again."; exit 1; }

tv() { "$adb_bin" -s "$dev" shell "$@" 2>&1 | tr -d '\r' | grep -v 'Broken pipe'; }

enabled_services() { v=$(tv settings get secure enabled_accessibility_services | tr -d '\n'); [ "$v" = null ] && v=""; echo "$v"; }
# Only our own entry is added or removed; other accessibility services you use stay enabled.
set_services() {
  if [ -z "$1" ]; then
    tv settings delete secure enabled_accessibility_services >/dev/null
    tv settings put secure accessibility_enabled 0 >/dev/null
  else
    tv "settings put secure enabled_accessibility_services '$1'" >/dev/null
    tv settings put secure accessibility_enabled 1 >/dev/null
  fi
}

# Git Bash on Windows hands a native adb.exe Unix-style paths it cannot open; convert them when cygpath exists.
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s\n' "$1"; fi; }

push_script() {
  [ -f "$local_script" ] || { echo "Script not found: $local_script"; exit 1; }
  tmp=$(mktemp)
  tr -d '\r' < "$local_script" > "$tmp"           # the script must have Unix line endings on the TV
  if ! res=$("$adb_bin" -s "$dev" push "$(winpath "$tmp")" "$remote_script" 2>&1); then
    rm -f "$tmp"; echo "Could not copy the script to the TV: $res"; exit 1
  fi
  rm -f "$tmp"
  # adb push can leave the file writable by every app; only the adb shell user may change it.
  tv "chmod 755 $remote_script; chmod 600 /data/local/tmp/avlfix.log /data/local/tmp/avlfix-top.txt /data/local/tmp/avlfix-ui.xml 2>/dev/null; true" >/dev/null
  [ -n "$(tv "ls $remote_script 2>/dev/null")" ] || { echo "The script is not on the TV after copying - stopping."; exit 1; }
}

log_lines() { n=$(tv "wc -l < $app_log 2>/dev/null" | tr -d ' '); case $n in ''|*[!0-9]*) echo 0 ;; *) echo "$n" ;; esac; }

# Waits for a NEW line from the app (old lines from earlier runs are ignored).
wait_result() {
  i=0
  while [ $i -lt 45 ]; do
    sleep 4
    new=$(tv "tail -n +$(($1 + 1)) $app_log 2>/dev/null")
    case $new in *"script:"*|*"could not run"*) echo "$new"; return ;; esac
    i=$((i + 1))
  done
  echo "No result yet - check again with: fixes.sh <ip> status"
}

case $action in
  status)
    if [ -n "$(tv pm list packages local.avlfix)" ]; then echo "App:        installed"; else echo "App:        NOT installed  (run: fixes.sh <ip> install)"; fi
    perm=$(tv "ls -l $remote_script 2>/dev/null" | awk '{print $1}')
    if [ -z "$perm" ]; then echo "TV script:  MISSING        (run: fixes.sh <ip> install --script-only)"
    elif [ "$(echo "$perm" | cut -c9)" = w ]; then echo "TV script:  present but writable by every app ($perm)  (run: fixes.sh <ip> install --script-only)"
    else echo "TV script:  present, protected ($perm)"; fi
    case ":$(enabled_services):" in *":$component:"*) echo "Netflix button watcher: on" ;; *) echo "Netflix button watcher: OFF" ;; esac
    echo "--- last lines of the app log ---"
    tv "tail -n 6 $app_log 2>/dev/null"
    ;;

  install)
    if [ "$script_only" -eq 0 ]; then
      [ -f "$apk" ] || { echo "APK not found: $apk"; echo "Build it first (see README.md) or pass --apk FILE."; exit 1; }
      res=$("$adb_bin" -s "$dev" install -r "$(winpath "$apk")" 2>&1 | tr -d '\r')
      echo "$res" | tail -n 1
      case $res in *Success*) ;; *)
        case $res in *INCOMPATIBLE*|*"signatures do not match"*)
          echo "The installed app was signed with a different key. Uninstall it first (fixes.sh <ip> remove), then install again." ;; esac
        exit 1 ;;
      esac
    fi
    push_script
    cur=$(enabled_services)
    case ":$cur:" in *":$component:"*) ;; *) set_services "${cur:+$cur:}$component" ;; esac
    if [ "$script_only" -eq 1 ]; then
      echo "Script updated on the TV (nothing was run). Check it with: fixes.sh $tv_ip status"
      exit 0
    fi
    echo 'Installed. Running once now. If the TV asks "Allow USB debugging?" for avlfix@tv, tick "Always allow" and press OK.'
    before=$(log_lines)
    tv am broadcast -a local.avlfix.RUN -n local.avlfix/.RunReceiver >/dev/null
    wait_result "$before"
    ;;

  run)
    before=$(log_lines)
    tv am broadcast -a local.avlfix.RUN -n local.avlfix/.RunReceiver >/dev/null
    wait_result "$before"
    ;;

  remove)
    cur=$(enabled_services)
    set_services "$(echo ":$cur:" | sed -e "s#:$component:#:#" -e 's#^:##' -e 's#:$##')"
    "$adb_bin" -s "$dev" uninstall local.avlfix 2>&1 | tr -d '\r'
    tv "rm -f $remote_script /data/local/tmp/avlfix.log /data/local/tmp/avlfix.pid /data/local/tmp/avlfix-top.txt /data/local/tmp/avlfix-ui.xml" >/dev/null
    echo "Removed. The TV still remembers the avlfix@tv debugging key until you use"
    echo "Developer options > Revoke USB debugging authorizations."
    ;;
esac
