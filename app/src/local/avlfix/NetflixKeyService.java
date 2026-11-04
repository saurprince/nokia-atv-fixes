package local.avlfix;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

/**
 * The TV's key handler (RtkKeyInterceptService) only launches Netflix for the remote's infrared
 * Netflix code. Over Bluetooth the RC860 remote sends the same button as KEYCODE_BUTTON_12
 * (scan code 758), which nothing handles. This service watches key presses and opens Netflix for
 * that one key from that remote; every other key is passed through untouched.
 */
public class NetflixKeyService extends AccessibilityService {
    private static final String REMOTE = "RC860";
    private static final String NETFLIX = "com.netflix.ninja";
    private long lastLaunch;

    @Override
    protected boolean onKeyEvent(KeyEvent event) {
        if (event.getKeyCode() != KeyEvent.KEYCODE_BUTTON_12 || !fromRemote(event)) {
            return false;
        }
        if (event.getAction() == KeyEvent.ACTION_UP && SystemClock.elapsedRealtime() - lastLaunch > 1500) {
            lastLaunch = SystemClock.elapsedRealtime();
            launchNetflix();
        }
        return true;    // swallow both down and up so nothing else reacts to BUTTON_12
    }

    private boolean fromRemote(KeyEvent event) {
        InputDevice device = InputDevice.getDevice(event.getDeviceId());
        return device != null && REMOTE.equals(device.getName());
    }

    /** Same intent the TV's own key handler uses for the infrared Netflix button. */
    private void launchNetflix() {
        AvlLog log = new AvlLog(this);
        Intent key = new Intent("com.netflix.action.NETFLIX_KEY_START")
                .setClassName(NETFLIX, NETFLIX + ".MainActivity")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
        try {
            startActivity(key);
            log.write("Netflix button (Bluetooth BUTTON_12) -> opened Netflix");
            return;
        } catch (Exception e) {
            log.write("Netflix key intent refused (" + e.getClass().getSimpleName() + "), using normal launch");
        }
        Intent launch = getPackageManager().getLeanbackLaunchIntentForPackage(NETFLIX);
        if (launch == null) {
            launch = getPackageManager().getLaunchIntentForPackage(NETFLIX);
        }
        if (launch == null) {
            log.write("Netflix button pressed but Netflix is not installed");
            return;
        }
        startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        log.write("Netflix button (Bluetooth BUTTON_12) -> opened Netflix");
    }

    @Override
    protected void onServiceConnected() {
        new AvlLog(this).write("Netflix button watcher active");
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
    }

    @Override
    public void onInterrupt() {
    }
}
