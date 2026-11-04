# Trying a different home screen (an experiment)

**Status: one TV, one evening.** This is not one of the fixes in this repository and nothing here is needed for them. It records what happened when the
[cleanyourtv](https://github.com/Gathin23/cleanyourtv) launcher (an Apple-TV-style app grid, MIT licensed) was tried on the tested Nokia "ATV R2"
(Android 11, build `RTT7.220308.001`). This repository contains none of its code and offers no APK; get the source and the build steps from that project.

## What was changed on the TV

- One app installed: `com.gathin.tvhome` (the launcher), built from its source without code changes (only the build setup was adapted to compile without Gradle).
- The stock launcher `com.google.android.tvlauncher` switched off by hand (see below why). The `debloat` script in this repository still refuses to do that, on purpose.
- One theme (`cinematic`, from that project) pushed to the launcher's own folder.
- Not done: none of the launcher's optional accessibility services was enabled, and no extra permission was granted to it.

## What we found

- **Making it the default Home needed the stock launcher switched off.** `cmd package set-home-activity` printed Success and the system listed the new launcher as the Home app,
  but the Home key kept starting the stock launcher. After `pm disable-user` on the stock launcher it worked: Home resolved to the new one and pressing Home from another app opened it.
- **Inputs.** The remote's physical Input key opens the TV's own source picker (`com.android.tv/.SelectInputActivity`), not anything in the stock launcher, and kept doing so.
  The launcher has its own Inputs menu, which listed HDMI1, HDMI2, HDMI3 and AV. `com.realtek.leanbacklauncher.partnercustomizer` was left untouched.
- **Restarts.** After two restarts Home, the role and the disabled apps stayed as set, and the Auto Volume fix re-applied itself both times (the TV's sound service confirmed it).
- **Start-up screen.** Both times the TV came up in its Live TV app on the last HDMI input ("No signal") instead of Home; pressing Home opened the new launcher. The boot log shows the Live TV app
  (`com.android.tv`) starting that input itself, so this is the TV's own "go back to the last source" behaviour, not the launcher. No start-up source option was found in the TV Settings
  (External Inputs and System > Power were checked; the other screens were not).
  It may have started after the Input key was tried, which is unproven. Waking from standby was not checked.
- **What goes away.** The stock home screen's recommendation and channel rows, and its Customize-channels screen. The new launcher is an app grid with a dock.

## How it measured (same TV, scripted arrow-key presses over ADB)

| | Stock Google home | New launcher, default look | New launcher, `cinematic` theme |
|---|---|---|---|
| Cold start (`am start -W` TotalTime) | 1441, 1453, 2775 ms | 1525, 919, 902 ms | 1114, 1061, 1079 ms |
| Launcher process memory | 162 to 217 MB | 104 MB | 106 MB |
| Frame time while moving between apps (typical / worst 1%) | not measured | 6 / 13 ms | 7 / 15 ms |
| Janky frames in a 12-key sequence | not measured | 2 of 457 (0.44%) | 3 of 307 (0.98%) |

Overall free memory stayed about the same (roughly 565 to 640 MB of 2 GB), because most memory is held by other apps. Three runs and a few hundred frames are small samples,
the stock launcher was timed in an earlier session, and a real remote was not used, so read the gaps as indicative only.

## If you want to try it (at your own risk)

1. Build the launcher from its project's source and install it **next to** the stock one, without switching anything off yet:
   `adb install -r <apk>`, then `adb shell am start -W -n com.gathin.tvhome/.MainActivity`. It must print `Status: ok` and show the launcher.
2. Save the undo commands below somewhere that is not on the TV.
3. Only then make it the default Home on this TV:

```
adb shell pm disable-user --user 0 com.google.android.tvlauncher
adb shell cmd package set-home-activity --user 0 com.gathin.tvhome/.MainActivity
```

4. Check it for real: open an app such as Settings, press Home, and see that the new launcher appears.

**Undo** (run from a PC on the same network, with `<tv-ip>` the TV's address):

```
adb connect <tv-ip>:5555
adb -s <tv-ip>:5555 shell pm enable --user 0 com.google.android.tvlauncher
adb -s <tv-ip>:5555 shell cmd package set-home-activity --user 0 com.google.android.tvlauncher/.MainActivity
```

If the new launcher ever failed to start, Home would fall back to the TV's plain Settings screen until the undo is run from a PC, so do not skip step 2.

## Not tested

The Bluetooth remote's Netflix button after the change (its accessibility service stayed enabled), the voice button, an HDMI source that has a signal, waking from standby, and anything beyond one evening of use.

## Licences

The launcher is MIT licensed by its author and bundles open-source libraries (AndroidX, Kotlin) under their own licences. The `cinematic` wallpaper is public domain (CC0), credited in that project.
Not affiliated with it, or with Nokia, Google or Realtek.
