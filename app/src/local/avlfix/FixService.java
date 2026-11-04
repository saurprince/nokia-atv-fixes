package local.avlfix;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.os.PowerManager;
import android.os.SystemClock;

import java.io.File;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.nio.file.Files;

/**
 * The Nokia TV firmware (V8-T851TNF-LF2V287) keeps "Auto Volume = Auto" across a restart but does
 * not apply it to the sound chip until the setting is changed again. After each boot this service
 * runs /data/local/tmp/avlfix.sh through the TV's own debugging port; the script switches Auto
 * Volume Off and back to Auto in Sound adjustments, checking the screen before every OK press.
 */
public class FixService extends Service {
    static final String EXTRA_BOOT = "boot";
    private static final String SCRIPT = "/data/local/tmp/avlfix.sh";
    private static volatile boolean running;

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel("avlfix", getString(R.string.app_name),
                NotificationManager.IMPORTANCE_LOW));
        Notification n = new Notification.Builder(this, "avlfix")
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .setContentTitle(getString(R.string.app_name))
                .setContentText(getString(R.string.notification_text))
                .build();
        startForeground(1, n);

        final boolean boot = intent != null && intent.getBooleanExtra(EXTRA_BOOT, false);
        if (running) {
            return START_NOT_STICKY;
        }
        running = true;
        new Thread(() -> {
            try {
                run(boot);
            } finally {
                running = false;
                stopForeground(true);
                stopSelf();
            }
        }, "avlfix").start();
        return START_NOT_STICKY;
    }

    private void run(boolean boot) {
        AvlLog log = new AvlLog(this);
        if (boot) {
            long wait = 90000 - SystemClock.elapsedRealtime();     // let the TV finish starting up
            log.write("TV started - re-applying Auto Volume in " + Math.max(0, wait) / 1000 + "s");
            if (wait > 0) {
                SystemClock.sleep(wait);
            }
        } else {
            log.write("manual run");
        }
        waitForScreenOn(log);

        try (AdbClient adb = new AdbClient("127.0.0.1", 5555)) {
            adb.connect(keyPair(), "avlfix@tv", 120000, log);
            String out = adb.shell("[ -f " + SCRIPT + " ] || { echo 'script missing: " + SCRIPT + "'; exit; }; "
                    + "sh " + SCRIPT + " once >/dev/null 2>&1; tail -n 2 /data/local/tmp/avlfix.log", 120000);
            log.write("script: " + out.trim().replace("\n", " | "));
        } catch (Exception e) {
            log.write("could not run the fix: " + e);
        }
    }

    /** After a power cut the TV may start in standby; wait until the screen is on. */
    private void waitForScreenOn(AvlLog log) {
        PowerManager pm = getSystemService(PowerManager.class);
        if (pm.isInteractive()) {
            return;
        }
        log.write("screen is off - waiting for it to turn on");
        while (!pm.isInteractive()) {
            SystemClock.sleep(5000);
        }
        SystemClock.sleep(10000);
    }

    /** This app's ADB key, created on first use and kept in its private storage. */
    private KeyPair keyPair() throws Exception {
        File priv = new File(getFilesDir(), "adbkey");
        File pub = new File(getFilesDir(), "adbkey.pub");
        KeyFactory kf = KeyFactory.getInstance("RSA");
        if (priv.exists() && pub.exists()) {
            return new KeyPair(kf.generatePublic(new X509EncodedKeySpec(Files.readAllBytes(pub.toPath()))),
                    kf.generatePrivate(new PKCS8EncodedKeySpec(Files.readAllBytes(priv.toPath()))));
        }
        KeyPairGenerator g = KeyPairGenerator.getInstance("RSA");
        g.initialize(2048);
        KeyPair kp = g.generateKeyPair();
        Files.write(priv.toPath(), kp.getPrivate().getEncoded());
        Files.write(pub.toPath(), kp.getPublic().getEncoded());
        return kp;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
