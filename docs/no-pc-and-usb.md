# No PC? What a USB stick or a phone can do

## The honest answer about USB sticks

**A USB stick cannot clean up an Android TV by itself.** An unrooted Android TV never runs scripts from a USB stick,
and switching apps off (`pm disable-user`) needs the identity of the *adb shell*, which only a debugging connection gives.
Ordinary apps cannot do it.

What a stick *can* do:

- **Carry the files to a PC.** Put this project, and Google's [platform-tools](https://developer.android.com/tools/releases/platform-tools)
  (the `adb` program), on a stick and use any Windows, Mac or Linux PC on your Wi-Fi. The scripts work from any folder.
- **Carry the APK to the TV.** With a file-manager app on the TV and the "install unknown apps" permission you can install `avlfix.apk` from a stick.
  That is not enough on its own: the helper script still has to be copied to the TV and the Netflix watcher switched on
  ([manual-steps.md](manual-steps.md), step 4), which needs `adb` once.

## An Android phone with Termux (untested)

The two `.sh` scripts only use `adb` and plain shell, so they should run in [Termux](https://termux.dev) on an Android phone:

```
pkg install android-tools
bash scripts/debloat.sh <tv-ip> status
```

Both devices must be on the same Wi-Fi. This was **not** tested; tell us if it works or what breaks.

## What would make it truly PC-free (not built)

The Auto Volume app already talks to the TV's own debug port, so a "setup screen" in the same app could apply the app list from a file on a USB stick
without a PC. It would still need the TV's network debugging port to be on and the one-time **Allow USB debugging?** approval,
and that port cannot be switched on from the TV's settings on every model. If you want this, it is a good first contribution.
