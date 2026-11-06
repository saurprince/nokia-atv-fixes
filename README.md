# nokia-atv-fixes

Small, reversible fixes for the **Nokia Smart TV "ATV R2"** (Android 11, Realtek RTD285O, made by SCBC), for example the 55-inch 4K model with Onkyo sound.
TVs on the same platform (for example the Compac and Sanyo "ATV R2") may behave the same, but only the Nokia was tested.

**Is this your TV?** Open Settings > Device Preferences > About. It matches if **Model** says `ATV R2`, **Android TV OS version** is `11`, and **Android TV OS build** is `RTT7.220308.001`
(the **Netflix ESN** line there starts with `NFANDROID2-PRV-SCBC2019RT51UHDANDROIDTV-SCBC=ATV=R2`). Other builds may differ: check `debloat ... status` before applying anything.

| Fix | What it does |
|---|---|
| **Auto Volume** | After a restart the sound menu says *Auto Volume: Auto* but the TV does not apply it until it is switched Off and back to Auto. A tiny app does that by itself after every boot, once the TV's start-up rush is over (about two minutes after power-on, see [docs/startup-time.md](docs/startup-time.md)). |
| **Netflix button** | The Bluetooth remote's Netflix button does nothing, because the TV only understands the infrared version of that button. A tiny accessibility service opens Netflix when it sees the Bluetooth button. |
| **App list** | A tested list of 12 preinstalled apps you can switch off, and a list of untested candidates. Nothing is uninstalled; one command switches everything back on. |

**You do not need an AI assistant.** Everything here is a plain script or a plain `adb` command that you can read and run yourself.
This project was developed with an AI assistant's help; the scripts do not use one.

> **Use at your own risk.** Everything is reversible, but it was tested on one TV only. You are changing the software of your own device;
> that may affect warranty or support. Read [Safety and security](#safety-and-security) first.

## What you need

- A PC on the same network as the TV (Windows, macOS or Linux), or an Android phone with Termux ([untested](docs/no-pc-and-usb.md)).
  A USB stick alone is **not** enough, see [docs/no-pc-and-usb.md](docs/no-pc-and-usb.md).
- `adb` from Google's [platform-tools](https://developer.android.com/tools/releases/platform-tools), on your PATH.
- On the TV: Settings > Device Preferences > About, press **Build** seven times, then Settings > Device Preferences > Developer options > switch **USB debugging** on
  (menu names differ slightly between TVs). On the tested TV this also lets a PC connect over Wi-Fi on port 5555; a TV's USB ports are normally host ports and cannot be used as a debugging cable.
- The TV's IP address (Settings > Network). Give it a fixed address in your router (a DHCP reservation): on the tested TV the address changed once and every script needs it.
- Check the connection: `adb connect <tv-ip>:5555`, then `adb devices`. The TV shows **Allow USB debugging?** the first time; tick *Always allow* and press OK.
  `adb devices` must say `device`, not `unauthorized`.

## 1. Switch off apps you do not need

Windows, easiest: double-click **`windows-start.bat`** and answer the questions (choose 1 first; it only shows what would change).

Windows, PowerShell (`-ExecutionPolicy Bypass` is needed because the scripts are unsigned):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\debloat.ps1 192.168.1.20 status
powershell -ExecutionPolicy Bypass -File scripts\debloat.ps1 192.168.1.20 apply
powershell -ExecutionPolicy Bypass -File scripts\debloat.ps1 192.168.1.20 restore        # undo
```

Linux, macOS, Git Bash, Termux:

```bash
bash scripts/debloat.sh 192.168.1.20 status
bash scripts/debloat.sh 192.168.1.20 apply
bash scripts/debloat.sh 192.168.1.20 restore                                              # undo
```

`apply` first saves a backup in `tv-backup-<date>` (the list of apps on your TV: do not publish it), then disables every app in
[`debloat/nokia-atv-r2-disable-list.txt`](debloat/nokia-atv-r2-disable-list.txt). It refuses to touch the remote, voice, inputs, launcher,
Wi-Fi/Bluetooth or Google services (add `-Force` / `--force` only if you know what you are doing).
Restart the TV afterwards and check your apps, remote and voice. What each app is: [docs/nokia-atv-r2.md](docs/nokia-atv-r2.md).
**Remove the TalkBack line from the list first if anyone using the TV needs the screen reader.**

## 2. Install the Auto Volume and Netflix fixes

**Easiest: download the ready-made app.** Get `avlfix-v3.0.apk` and `SHA256SUMS.txt` from the
[latest release](https://github.com/saurprince/nokia-atv-fixes/releases/latest) and check that the file's SHA-256 matches `SHA256SUMS.txt`
(PowerShell: `Get-FileHash avlfix-v3.0.apk`; Linux/macOS: `sha256sum avlfix-v3.0.apk`). Install it with the script, not by sideloading alone,
because the helper script must be copied to the TV as well:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\fixes.ps1 192.168.1.20 install -Apk C:\path\to\avlfix-v3.0.apk
```

```bash
bash scripts/fixes.sh 192.168.1.20 install --apk path/to/avlfix-v3.0.apk
```

**Or build it yourself** (Windows; needs the Android SDK and JDK 17+, [details](app/build.ps1)), which is safer if you would rather not run a downloaded file:

```powershell
powershell -ExecutionPolicy Bypass -File app\build.ps1        # creates app\avlfix.apk and app\avlfix.keystore
powershell -ExecutionPolicy Bypass -File scripts\fixes.ps1 192.168.1.20 install
```

An app built by you is signed with your own key, so it cannot update the release version (or the other way round): run `fixes ... remove` first when switching.

`install` installs the app, copies the helper script to the TV, turns the Netflix-button watcher on, and runs the Auto Volume fix once.
**The TV will ask "Allow USB debugging?" for `avlfix@tv`: tick *Always allow* and press OK.**
Keep `app\avlfix.keystore`: Android only updates an app with an APK signed by the same key.
Check at any time with `scripts\fixes.ps1 <ip> status`; remove everything with `scripts\fixes.ps1 <ip> remove`.

## No scripts at all?

[docs/manual-steps.md](docs/manual-steps.md) lists every `adb` command, so you can type them yourself.

## Safety and security

- **The fixes keep network debugging on.** The Auto Volume app talks to the TV's own debug port (127.0.0.1:5555) after every boot,
  so port 5555 stays open on your home network. The connection is unencrypted. A new computer still needs your approval on the TV screen,
  but switch debugging off if you do not use these fixes. The app's key (`avlfix@tv`) lives in the app's private storage.
- **The app can run shell commands on the TV.** Its source is small (`app/src`); read it, and build it yourself rather than installing an APK from a stranger.
- **The Netflix watcher is an accessibility service**, which means Android shows it every key press from every input device, including a Bluetooth keyboard.
  The code acts only on `KEYCODE_BUTTON_12` from the device named `RC860` and ignores, logs and stores nothing else
  (see [`NetflixKeyService.java`](app/src/local/avlfix/NetflixKeyService.java)). It declares no screen-reading permission.
- Any app on the TV can ask the Auto Volume app to run (the sound menu then flashes briefly); that is a nuisance, not a hole.
- `adb push` from Windows leaves files writable by every app. `fixes ... install` fixes the permissions of the on-TV script; `fixes ... status` warns if they are wrong.
- Debug backups and logs can contain Wi-Fi names, device names and addresses. Do not post them.

## What was tested

Real TV: Nokia "ATV R2" (55-inch 4K, Onkyo sound), Android 11, Android TV OS build RTT7.220308.001 (security patch 5 June 2022, kernel 4.14.94+), firmware V8-T851TNF-LF2V287, 2 GB RAM, Bluetooth remote RC860.

| Tested | Result |
|---|---|
| The 12-app list: restarts, Netflix, YouTube, voice, Bluetooth remote | worked; the 12 apps stayed off across restarts |
| `debloat` status / apply / restore, incl. screensaver restore | worked in Windows PowerShell 5.1, PowerShell 7 and Git Bash (a real round trip on the TV) |
| Protected-app guard | refused Bluetooth and voice packages, changed nothing |
| Auto Volume fix after real restarts | re-applied each time (confirmed in the TV's sound-service log; confirmed by ear once) |
| Netflix button over Bluetooth | opened Netflix |
| `fixes install --script-only`, `fixes status` | worked in PowerShell 5.1 and bash |
| **Not tested** | Linux, macOS, Termux; any other TV; the Netflix watcher's key code on other remotes |

## Related projects

[cleanyourtv](https://github.com/Gathin23/cleanyourtv) is a larger, general project for debloating Android TV with per-model lists and a replacement launcher.
This repository is separate and not affiliated with it; its list for the same SCBC platform is where [`debloat/nokia-atv-r2-candidates.txt`](debloat/nokia-atv-r2-candidates.txt) comes from.

## More

- [docs/how-it-works.md](docs/how-it-works.md): why the two bugs happen and how the fixes work
- [docs/wifi-notes.md](docs/wifi-notes.md): this TV's Wi-Fi is a 2.4 GHz-only USB module, and why it drops
- [docs/no-pc-and-usb.md](docs/no-pc-and-usb.md): what a USB stick or a phone can do
- [docs/startup-time.md](docs/startup-time.md): why this TV takes a while to start, what was measured and what did not help (one TV)
- [docs/launcher-trial.md](docs/launcher-trial.md): an experiment with a different home screen (one TV, one evening; optional)

MIT licensed ([LICENSE](LICENSE)). Not affiliated with or endorsed by Nokia, Google, Netflix, Realtek or SCBC; product names belong to their owners.
