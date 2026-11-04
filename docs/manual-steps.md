# Every step by hand (no scripts, no AI)

These are the exact commands the scripts run. Replace `192.168.1.20` with your TV's address. In PowerShell write `adb shell "..."` with the
command in double quotes where it contains `;` or `'`.

## 0. Connect

```
adb connect 192.168.1.20:5555
adb devices
```

`adb devices` must show `192.168.1.20:5555    device`. If it says `unauthorized`, accept **Allow USB debugging?** on the TV.
Use `adb -s 192.168.1.20:5555 ...` if more than one device is listed.

## 1. Back up first

```
adb shell pm list packages -e   > packages-enabled.txt
adb shell pm list packages -d   > packages-disabled-before.txt
adb shell settings get secure screensaver_components         > screensaver-components.txt
adb shell settings get secure screensaver_default_component  > screensaver-default.txt
```

These files list the apps on your TV. Keep them; do not post them.

## 2. Switch the apps off (nothing is uninstalled)

```
adb shell pm disable-user --user 0 com.google.android.videos
adb shell pm disable-user --user 0 com.google.android.tvrecommendations
adb shell pm disable-user --user 0 com.google.android.play.games
adb shell pm disable-user --user 0 com.google.android.backdrop
adb shell pm disable-user --user 0 com.google.android.youtube.tvmusic
adb shell pm disable-user --user 0 com.google.android.feedback
adb shell pm disable-user --user 0 com.google.android.marvin.talkback
adb shell pm disable-user --user 0 com.google.android.syncadapters.calendar
adb shell pm disable-user --user 0 com.android.printspooler
adb shell pm disable-user --user 0 com.apps.wifihotspot
adb shell pm disable-user --user 0 com.apps.eshow
adb shell pm disable-user --user 0 com.apps.esticker
```

(Skip `com.google.android.marvin.talkback` if anyone needs the screen reader.) Each line answers `new state: disabled-user`.

Ambient mode (`com.google.android.backdrop`) is the screensaver; point the TV at the plain built-in one so it never uses a disabled app:

```
adb shell settings put secure screensaver_components com.android.dreams.basic/.Colors
adb shell settings put secure screensaver_default_component com.android.dreams.basic/.Colors
```

Restart the TV (`adb reboot`) and check your apps, remote and voice. List what is off: `adb shell pm list packages -d`.

## 3. Undo

```
adb shell pm enable --user 0 com.google.android.videos
   ... one line per package above ...
adb shell settings put secure screensaver_components com.google.android.backdrop/.Backdrop
```

If your backup shows a different screensaver value, put that one back. If it says `null`, use `adb shell settings delete secure screensaver_components`.

## 4. The Auto Volume and Netflix fixes

```
adb install -r app/avlfix.apk
adb push device/avlfix.sh /data/local/tmp/avlfix.sh
adb shell chmod 755 /data/local/tmp/avlfix.sh
adb shell settings get secure enabled_accessibility_services
```

If the last command prints `null`, turn the Netflix watcher on with:

```
adb shell settings put secure enabled_accessibility_services local.avlfix/local.avlfix.NetflixKeyService
adb shell settings put secure accessibility_enabled 1
```

If it prints other services, join them with colons instead, e.g. `other.app/other.app.Service:local.avlfix/local.avlfix.NetflixKeyService`.

Run the Auto Volume fix once (the sound menu appears for about 20-30 seconds; the TV asks **Allow USB debugging?** for `avlfix@tv` the first time):

```
adb shell am broadcast -a local.avlfix.RUN -n local.avlfix/.RunReceiver
adb shell tail -n 5 /sdcard/Android/data/local.avlfix/files/avlfix.log
```

The log ends with `Auto Volume re-applied (Off -> Auto ...)`. From then on it runs by itself after every restart.
(If you copied the script from Windows, make sure it has Unix line endings: no `^M` at the line ends.)

## 5. Remove the fixes

```
adb shell settings delete secure enabled_accessibility_services     # only if nothing else uses accessibility
adb shell settings put secure accessibility_enabled 0
adb uninstall local.avlfix
adb shell rm -f /data/local/tmp/avlfix.sh /data/local/tmp/avlfix.log /data/local/tmp/avlfix-top.txt /data/local/tmp/avlfix-ui.xml
```

The TV remembers the `avlfix@tv` key until you choose **Revoke USB debugging authorizations** in Developer options.
