# Why the TV takes a while to start

**Status: one TV, a handful of restarts (early November 2026).** Read-only measurements from the TV's own logs, plus a few experiments. Boots differ from each other by seconds
(and in the app phase by more), so read every number as indicative. Tested hardware: see [how-it-works.md](how-it-works.md).

## What happens after power-on

Seconds since the kernel started. The bootloader and logo time before that was not measured.

| Seconds | What happens |
|---|---|
| 0 to 14 | the kernel and the vendor (Realtek) services start; Android's first process appears at about 14 s |
| 14 to 23 | Android preloads its classes |
| 23 to 37 | system services start, installed apps are scanned (about 3 s, nothing was re-optimised), the screen is enabled at about 37 s |
| 47 to 50 | the Live TV screen starts (the TV's own "go back to the last input" behaviour, see [launcher-trial.md](launcher-trial.md)) |
| about 35 to 120-145 | about 80 processes start in all: first system and vendor services, then about 30 apps that are woken by their own start-up receivers (streaming apps, Google services) |
| about 105 | the "boot finished" broadcast reaches the Auto Volume app; Android hands it to the apps one after another |
| about 128 to 143 | the Auto Volume fix has finished (it takes about 25 s) |

Times come from the `boot_progress_*` lines in `adb logcat -b events -d` and the `Start proc` lines in `adb logcat -b all -d`.

## Why it is slow

The first 50 s or so is the TV's firmware and chip (four cores, up to 1.1 GHz) and cannot be changed from outside. The long part after it is memory and storage:
the TV has 2 GB of RAM, and about 80 processes start within a minute or two. Over the first 4 to 7 minutes of three boots the system read 2.9 to 3.9 GB from storage and pushed
0.2 to 0.5 GB into compressed swap (`/proc/vmstat`: `pgpgin`, `pswpout`). The load average (tasks waiting for a core, `/proc/loadavg`) was 38 at two minutes in the one boot where it was read then,
and 20 to 23 at four and a half minutes in all three.

## What was tried

- **Starting the Auto Volume fix earlier.** A manual trigger sent at 76 s (`am broadcast -a local.avlfix.RUN ...`) waited in the same queue as the boot broadcast, arrived after the app's own start and was ignored.
  An experimental build (not published) that started the menu run at 50 s needed 74 s instead of about 25 s, could not confirm its result, and was retried 20 s later (confirmed at about 160 s).
  Its first attempt ended at about the same time (about 125 s) as the normal run that starts at about 105 s and ends at about 128 s. So starting earlier gains nothing and only keeps the sound panel on screen longer.
  The same build asked for a high receiver priority, and the boot broadcast then reached the app at 54 s instead of 105 s, but that does not help for the same reason.
- **Stopping three rarely used apps from starting at boot** (a video player, the discontinued Google Play Music and a VPN app) with
  `adb shell cmd appops set <package> RUN_ANY_IN_BACKGROUND ignore` (undo: `allow`). They still started at boot, and two of them were stopped again afterwards.
  The start-up rush ended at 144 s in the one boot without this and at 115 s and 122 s in the two boots with it, with less swap used. With so few boots that is a hint at most.
- **Disabling the discontinued Google Play Music app on its own.** Free memory changed by about 10 MB, within noise, so it is not on the app list.
- **Faster key presses.** `cmd input` has no shell commands on this Android 11 build, so each key press (a new Java process) still costs about 1.3 s, and more while the TV is busy starting.

## What you can do

- Use standby from the remote instead of restarting: only a cold boot goes through all of this and loses the Auto Volume setting. Waking from standby was not measured.
- After a restart, give the TV about two and a half minutes before you expect the sound fix. The sound menu will appear on screen for about 25 s.
- Switching off apps you never use ([the app list](nokia-atv-r2.md)) may shorten the rush; how much was not measured.

## Not measured

One TV and one firmware; the time before the kernel starts; waking from standby; the effect of switching off more apps; boots with a different set of installed apps.
