#!/usr/bin/env bash
# debloat.sh - back up, disable and restore apps on an Android TV over Wi-Fi ADB. No AI needed.
# Works on Linux, macOS, Git Bash on Windows, and Termux on an Android phone (needs the "adb" tool).
# Nothing is uninstalled: apps are switched off with "pm disable-user" and can be switched back on.
#
#   bash scripts/debloat.sh <tv-ip> status             show the state of every app in the list (changes nothing)
#   bash scripts/debloat.sh <tv-ip> apply              back up, then disable every app in the list
#   bash scripts/debloat.sh <tv-ip> restore [pkg...]   re-enable the list, or only the packages you name
#
# Options after the action:
#   --list FILE    package list (default: debloat/nokia-atv-r2-disable-list.txt)
#   --backup DIR   backup folder (default: ./tv-backup-<date>; "restore" uses the newest one)
#   --force        allow apps on the protected list (remote, voice, inputs, launcher...). Can break the TV.
set -u
export MSYS_NO_PATHCONV=1   # Git Bash on Windows must not rewrite /data/... style arguments
here="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<'EOF'
Usage: bash scripts/debloat.sh <tv-ip> status|apply|restore [package...] [--list FILE] [--backup DIR] [--force]
EOF
  exit 1
}

[ $# -ge 2 ] || usage
tv_ip=$1; action=$2; shift 2
case $action in status|apply|restore) ;; *) usage ;; esac
list="$here/../debloat/nokia-atv-r2-disable-list.txt"; backup=""; force=0; explicit=""
while [ $# -gt 0 ]; do
  case $1 in
    --list)   [ $# -ge 2 ] || usage; list=$2; shift 2 ;;
    --backup) [ $# -ge 2 ] || usage; backup=$2; shift 2 ;;
    --force)  force=1; shift ;;
    -*)       usage ;;
    *)        explicit="$explicit $1"; shift ;;
  esac
done

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
read_list() { [ -f "$1" ] || { echo "Package list not found: $1" >&2; exit 1; }; sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep -v '^$'; }

# Apps that keep the remote, voice, inputs, Wi-Fi/Bluetooth, launcher or Google services working.
is_protected() {
  case $1 in
    com.realtek.*|com.android.bluetooth*|com.android.systemui*|com.android.tv|com.android.tv.*|\
    com.android.providers.*|com.android.settings*|com.android.inputdevices|com.android.shell|\
    com.android.vending|com.google.android.packageinstaller|com.google.android.tvlauncher|\
    com.google.android.katniss*|com.google.android.tv.remote.service|com.google.android.gms*|\
    com.google.android.gsf|com.google.android.inputmethod.*|com.google.android.tts|\
    com.google.android.tungsten.*|com.google.android.apps.initsetup|com.google.android.youtube.tv|\
    com.google.android.webview|com.apps.bluetoothremote|com.apps.fivekey|com.apps.smartkey|\
    com.apps.virtualkey|com.apps.sys|com.apps.puresound|com.apps.usbmediaplayer|com.apps.ota|\
    com.apps.authota|com.functions.autopair|com.netflix.ninja|com.amazon.amazonvideo.*|\
    local.avlfix|android) return 0 ;;
  esac
  return 1
}

echo "TV: $(tv getprop ro.product.model), Android $(tv getprop ro.build.version.release), build $(tv getprop ro.build.display.id)"
listed=$(read_list "$list") || exit 1
installed=$(tv pm list packages | sed 's/^package://')
disabled=$(tv pm list packages -d | sed 's/^package://')

case $action in
  status)
    echo "List: $list"
    for p in $listed; do
      if echo "$disabled" | grep -qx "$p"; then s=disabled
      elif echo "$installed" | grep -qx "$p"; then s=ENABLED
      else s="not installed"; fi
      is_protected "$p" && s="$s   (PROTECTED - will be refused)"
      printf '%-48s %s\n' "$p" "$s"
    done
    ;;

  apply)
    blocked=""
    for p in $listed; do is_protected "$p" && blocked="$blocked $p"; done
    if [ -n "$blocked" ] && [ "$force" -eq 0 ]; then
      echo "Refusing: these are on the protected list (remote, voice, inputs, launcher, Wi-Fi/Bluetooth, Google services):"
      for p in $blocked; do echo "  $p"; done
      echo "Remove them from the list, or add --force if you really know what you are doing."
      exit 1
    fi

    dir=${backup:-./tv-backup-$(date +%Y-%m-%d)}
    mkdir -p "$dir"
    tv pm list packages -e | sed 's/^package://' | sort > "$dir/packages-enabled.txt"
    echo "$disabled" | sort > "$dir/packages-disabled-before.txt"
    { echo "components=$(tv settings get secure screensaver_components)"
      echo "default=$(tv settings get secure screensaver_default_component)"; } > "$dir/screensaver.txt"
    echo "$(date '+%Y-%m-%dT%H:%M:%S')  $(tv getprop ro.product.model)  build $(tv getprop ro.build.display.id)" > "$dir/info.txt"
    echo "Backup saved in $dir (it lists the apps on your TV - do not publish it)."

    for p in $listed; do
      if ! echo "$installed" | grep -qx "$p"; then printf '%-48s not installed - skipped\n' "$p"; continue; fi
      if echo "$disabled" | grep -qx "$p"; then printf '%-48s already disabled\n' "$p"; continue; fi
      r=$(tv pm disable-user --user 0 "$p")
      printf '%-48s %s\n' "$p" "${r##*new state: }"
    done

    # Ambient mode is the screensaver; switch to the plain built-in one so the TV never points at a disabled app.
    if echo "$listed" | grep -qx com.google.android.backdrop && tv pm list packages com.android.dreams.basic | grep -q dreams.basic; then
      tv settings put secure screensaver_components com.android.dreams.basic/.Colors >/dev/null
      tv settings put secure screensaver_default_component com.android.dreams.basic/.Colors >/dev/null
      echo 'Screensaver set to the built-in "Colors" screensaver (the old setting is in the backup).'
    fi
    echo
    echo "Done. Restart the TV once and check that your apps, remote and voice still work."
    echo "Undo any time with:  bash scripts/debloat.sh $tv_ip restore"
    ;;

  restore)
    targets=${explicit:-$listed}
    for p in $targets; do
      if ! echo "$installed" | grep -qx "$p"; then printf '%-48s not installed - skipped\n' "$p"; continue; fi
      r=$(tv pm enable --user 0 "$p")
      printf '%-48s %s\n' "$p" "${r##*new state: }"
    done
    if echo "$targets" | tr ' ' '\n' | grep -qx com.google.android.backdrop; then
      dir=${backup:-$(ls -d ./tv-backup-* 2>/dev/null | sort | tail -n 1)}
      if [ -n "$dir" ] && [ -f "$dir/screensaver.txt" ]; then
        while IFS='=' read -r k v; do
          case $k in components) key=screensaver_components ;; default) key=screensaver_default_component ;; *) continue ;; esac
          if [ -z "$v" ] || [ "$v" = null ]; then tv settings delete secure "$key" >/dev/null
          else tv "settings put secure $key '$v'" >/dev/null; fi
        done < "$dir/screensaver.txt"
        echo "Screensaver settings restored from $dir"
      else
        echo "No backup folder found. To get Ambient mode back run:"
        echo "  adb shell settings put secure screensaver_components com.google.android.backdrop/.Backdrop"
      fi
    fi
    echo "Done. Restart the TV if anything still looks off."
    ;;
esac
