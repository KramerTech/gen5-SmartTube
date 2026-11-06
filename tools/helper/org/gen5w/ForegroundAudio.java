package org.gen5w;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.media.AudioManager;
import android.os.Handler;
import android.os.Looper;
import java.lang.ref.WeakReference;

/** Retain granted focus across player -> browse, never across leaving SmartTube. */
public final class ForegroundAudio {
    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private static WeakReference<Activity> resumed = new WeakReference<Activity>(null);
    private static AudioManager manager;
    private static AudioManager.OnAudioFocusChangeListener delegate;
    private static final String NOTICE = "BlueLink modem data is blocked. Connect the head unit to Wi-Fi, "
            + "such as your phone's hotspot. Android Auto internet sharing is not yet verified for this app. "
            + "The full NEMESIS package installs the background network service; an APK alone is insufficient.";
    private ForegroundAudio() {}

    private static final AudioManager.OnAudioFocusChangeListener PROXY =
            new AudioManager.OnAudioFocusChangeListener() {
        public void onAudioFocusChange(int change) {
            AudioManager.OnAudioFocusChangeListener listener;
            synchronized (ForegroundAudio.class) {
                listener = delegate;
                if (change == AudioManager.AUDIOFOCUS_LOSS) {
                    delegate = null;
                }
            }
            // ExoPlayer still handles ducking/pause. Never synthesize GAIN or restart playback.
            if (listener != null) listener.onAudioFocusChange(change);
        }
    };
    private static final Runnable LEAVE = new Runnable() {
        public void run() {
            synchronized (ForegroundAudio.class) {
                if (resumed.get() == null) release();
            }
        }
    };

    public static synchronized void onResume(Activity activity) {
        resumed = new WeakReference<Activity>(activity);
        MAIN.removeCallbacks(LEAVE);
        if (!activity.getSharedPreferences("gen5w", Context.MODE_PRIVATE).getBoolean("gen5w_wifi_notice", false)) {
            new AlertDialog.Builder(activity).setTitle("Wi-Fi required").setMessage(NOTICE)
                    .setPositiveButton(android.R.string.ok, null).show();
            activity.getSharedPreferences("gen5w", Context.MODE_PRIVATE).edit().putBoolean("gen5w_wifi_notice", true).apply();
        }
    }

    public static synchronized void onPause(Activity activity) {
        if (resumed.get() == activity) resumed.clear();
        // Android pauses the player before resuming the browse Activity. Do not
        // briefly abandon focus and resume the OEM radio during this handoff.
        MAIN.removeCallbacks(LEAVE);
        MAIN.postDelayed(LEAVE, 700);
    }

    public static synchronized int request(AudioManager audio,
            AudioManager.OnAudioFocusChangeListener listener, int stream, int gain) {
        AudioManager.OnAudioFocusChangeListener previous = delegate;
        delegate = listener;
        // Standard Android focus API, with the same transient gain as Jellyfin.
        // No OEM media-mode broadcasts or hidden Hyundai requestAudioFocus overload.
        int result = audio.requestAudioFocus(PROXY, stream, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT);
        if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            manager = audio;
            if (resumed.get() == null) {
                MAIN.removeCallbacks(LEAVE);
                MAIN.postDelayed(LEAVE, 700);
            }
        } else {
            delegate = previous;
        }
        return result;
    }

    public static synchronized int abandon(AudioManager audio,
            AudioManager.OnAudioFocusChangeListener listener) {
        if (delegate == listener) delegate = null; // Released player must not receive callbacks.
        if (resumed.get() == null) {
            MAIN.removeCallbacks(LEAVE);
            MAIN.postDelayed(LEAVE, 700);
        }
        return AudioManager.AUDIOFOCUS_REQUEST_GRANTED;
    }

    private static void release() {
        // Notify a still-live/background player before dropping focus.
        AudioManager.OnAudioFocusChangeListener listener = delegate;
        delegate = null;
        if (listener != null) listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS);
        if (manager != null) manager.abandonAudioFocus(PROXY);
        manager = null;
    }
}
