package local.avlfix;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Manual trigger: adb shell am broadcast -a local.avlfix.RUN -n local.avlfix/.RunReceiver */
public class RunReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        context.startForegroundService(new Intent(context, FixService.class));
    }
}
