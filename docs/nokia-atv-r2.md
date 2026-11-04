# The Nokia "ATV R2" app list

How the list was made: on one TV, `adb shell pm list packages -f -u -i` and `adb shell ps` showed what is installed and what stays in memory; the apps below were switched off
together, and the TV was checked after restarts. Descriptions of vendor apps are inferred from their names and manifests, not from documentation.

## What `nokia-atv-r2-disable-list.txt` switches off

| Package | What it is | Notes |
|---|---|---|
| `com.google.android.videos` | Google TV / Play Movies & TV app | |
| `com.google.android.tvrecommendations` | recommendation rows on the home screen | the home screen still loads; the rows go |
| `com.google.android.play.games` | Google Play Games | |
| `com.google.android.backdrop` | "Ambient mode" screensaver | the scripts first point the TV at the built-in *Colors* screensaver |
| `com.google.android.youtube.tvmusic` | YouTube Music | |
| `com.google.android.feedback` | Google feedback / bug reporting | |
| `com.google.android.marvin.talkback` | TalkBack screen reader | **skip it if anyone needs the screen reader** |
| `com.google.android.syncadapters.calendar` | Google Calendar sync adapter | |
| `com.android.printspooler` | print spooler | |
| `com.apps.wifihotspot` | vendor Wi-Fi hotspot app | |
| `com.apps.eshow` | vendor "E-SHOW" app | name suggests a shop-display mode |
| `com.apps.esticker` | vendor "E-Sticker" app | purpose unclear; nothing depended on it. The cleanyourtv list for the same platform leaves it alone |

Effect on the tested TV: about 115 MB more free memory right after the first clean-up (`MemAvailable` 349 MB to 465 MB at that moment). Numbers vary with what is running.

## What the scripts refuse to switch off

The remote and voice (`com.google.android.katniss`, `com.google.android.tv.remote.service`, `com.apps.bluetoothremote`, `com.apps.fivekey`, `com.apps.smartkey`, `com.apps.virtualkey`, `com.functions.autopair`),
everything starting with `com.realtek.` (inputs, tuner, key handler, the home-screen helper that supplies the Inputs button),
Bluetooth, the system UI, Settings, Play Store and Play services, the launcher, the setup wizard (`com.google.android.tungsten.*`; other projects warn that disabling it can take over the home screen),
the keyboard and text-to-speech, the sound apps (`com.apps.puresound`), the update apps, Netflix, YouTube and Prime Video. See `scripts/common.ps1` for the full list.

## Candidates (untested here)

[`nokia-atv-r2-candidates.txt`](../debloat/nokia-atv-r2-candidates.txt) comes from the list for the same SCBC platform in the cleanyourtv project, plus one observation of ours.
Try a few at a time. `com.google.android.apps.mediashell` is Chromecast built-in: switch it off only if you never cast to the TV.

## Replacing the home screen?

Some projects replace the stock launcher with a lighter one. According to the cleanyourtv notes for this platform, the stock home screen gets its **Inputs** button from
`com.realtek.leanbacklauncher.partnercustomizer` (that package must stay on), so a replacement launcher has to provide its own inputs entry. This repository does not change the launcher.
That is about the on-screen button: the remote's physical Input key opens the TV's own source picker (`com.android.tv`) whichever launcher is installed.

The cleanyourtv launcher was later tried on this TV for one evening. [launcher-trial.md](launcher-trial.md) says what worked and what did not (for example, it only became the Home screen after the stock launcher
was switched off), and how to undo it. It is an experiment, not part of the fixes here.

## Firmware updates

A firmware update may switch apps back on or change the sound menu. Run `debloat ... status` afterwards; if the menu changed, `device/avlfix.sh` stops without pressing anything (see its log).
