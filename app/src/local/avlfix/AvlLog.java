package local.avlfix;

import android.content.Context;
import android.util.Log;

import java.io.File;
import java.io.FileWriter;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/** Logcat tag AvlFix, plus /sdcard/Android/data/local.avlfix/files/avlfix.log (readable over adb). */
final class AvlLog {
    static final String TAG = "AvlFix";
    private final File file;

    AvlLog(Context context) {
        File dir = context.getExternalFilesDir(null);
        file = dir == null ? null : new File(dir, "avlfix.log");
    }

    void write(String msg) {
        Log.i(TAG, msg);
        if (file == null) {
            return;
        }
        String stamp = new SimpleDateFormat("MM-dd HH:mm:ss", Locale.US).format(new Date());
        try (FileWriter w = new FileWriter(file, file.length() < 100_000)) {
            w.write(stamp + " " + msg + "\n");
        } catch (Exception ignored) {
        }
    }
}
