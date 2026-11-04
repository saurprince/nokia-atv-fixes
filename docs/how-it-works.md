# How the fixes work

Tested hardware: Nokia Smart TV, product `ATV R2`, maker SCBC, Realtek `rtd285o`, Android 11 (build `RTT7.220308.001`),
firmware `V8-T851TNF-LF2V287` (28 July 2022, security patch 2022-06-05), kernel `4.14.94+` (built 15 February 2023). The TV's own update app reported it as the latest version on 2026-10-20.
The Settings > About screen shows the same: Model `ATV R2`, Android TV OS version 11, build `RTT7.220308.001`. Netflix identifies the platform as `SCBC2019RT51UHDANDROIDTV`.

## Auto Volume does nothing after a restart

**Symptom.** After the TV is restarted or powered on from shutdown, Settings still shows *Auto Volume: Auto*, but loud parts stay loud.
Switching it Off and back to Auto makes it work. Standby from the remote does not cause this.

**Cause (as observed).** The TV's sound service (`CAQControl`, in the vendor `tvservice`) applies the setting to the audio chip only when it is *changed*
(its log shows `setAutoVolumeInternal onOff:0/1`), not when the saved value is loaded at boot. The value lives in vendor storage that a normal shell cannot read or write;
the settings provider, `service list` and the menu app's intents offer no way to call it directly. The only reachable path is the menu itself:
*Sound adjustments > Advanced Setting > Auto Volume*.

**The fix.**

1. `BootReceiver` (BOOT_COMPLETED) starts `FixService`, a short-lived foreground service.
2. It waits until about 90 seconds after boot and until the screen is on.
3. It connects to the TV's own debug port, `127.0.0.1:5555`, with its own RSA key (`avlfix@tv`, approved once on the TV; see `AdbClient.java`)
   and runs `sh /data/local/tmp/avlfix.sh once`.
4. `device/avlfix.sh` opens the sound menu (`am start -a com.realtek.tv.actionmenu.sound.SoundAdjustAction`), walks to Auto Volume with D-pad key events,
   chooses Off, then Auto, and closes the menu (20-30 s; Auto Volume is Off for about 4 s).

**Safety checks in the script.**
It reads the screen with `dumpsys activity top` (fast) and presses OK only when the highlighted row is exactly the expected one,
so it can never press the neighbouring *Reset* tab. It confirms each step in the TV's log (`AdvancedAutoVolumeFragment`, `setAutoVolume:Off/On`).
If the menu looks different (for example after a firmware update) it stops without pressing anything. If you set Auto Volume to Off yourself, it leaves it alone.
If it stops after switching to Off it writes a warning to the log so you can check the setting.

**Things that did not work (so you do not have to try them).**
- The first version used an accessibility service to click through the menu. The Auto Volume row did not react to accessibility clicks or taps on this TV, so key events over ADB are used.
- `input keyevent` costs about 1.3 s per call whatever the number of keys, and `uiautomator dump` about 2 s, so the script batches keys and uses `dumpsys activity top`.
- Triggering on wake from standby was the wrong trigger; only a cold boot loses the effect.

## The Netflix button over Bluetooth

The Bluetooth remote (`RC860`) sends the Netflix button as HID usage `0xc0051`, scan code 758, which Android maps to `KEYCODE_BUTTON_12` (199).
The TV's key handler (`com.realtek.keyinterceptserver`, `RtkKeyInterceptService`) only starts Netflix for its own infrared code (`KEYCODE_TCL_NETFLIX`),
so the Bluetooth press is logged as `ap decide result is 0` and ignored. It worked only when the remote happened to send infrared.

`NetflixKeyService` is an accessibility service that asks only to *filter key events* (`canRequestFilterKeyEvents`, no window content, no events from other apps).
For `KEYCODE_BUTTON_12` from the device named `RC860` it starts `com.netflix.action.NETFLIX_KEY_START` on `com.netflix.ninja/.MainActivity`
(the intent the TV's own handler uses), falling back to Netflix's normal launch intent, and consumes the key. Every other key is passed through untouched.
To adapt it to another remote, change `REMOTE` and the key code in the source; find them with `adb shell dumpsys input` and `adb shell getevent -l`.

## Files

| Path | Purpose |
|---|---|
| `app/src/local/avlfix/` | the Android app: `BootReceiver`, `FixService`, `AdbClient` (a small ADB client), `NetflixKeyService`, `RunReceiver`, `AvlLog` |
| `device/avlfix.sh` | runs on the TV; navigates the sound menu |
| `scripts/*.ps1`, `scripts/*.sh` | run on your PC or phone; install, check and remove the fixes; disable and restore apps |
| `debloat/` | the app lists |

Logs: the app writes `/sdcard/Android/data/local.avlfix/files/avlfix.log`, the script writes `/data/local/tmp/avlfix.log`; `adb logcat -s AvlFix` shows the app live.
