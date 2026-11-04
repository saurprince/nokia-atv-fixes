package local.avlfix;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Runs the fix once after every restart / power-on from shutdown (standby does not reboot). */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            context.startForegroundService(new Intent(context, FixService.class).putExtra(FixService.EXTRA_BOOT, true));
        }
    }
}
