package org.gen5w;

import android.os.Process;
import android.os.SystemClock;
import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.util.Properties;

/** APK-side startup gate; the root service enforces routing on existing sockets. */
public final class NetworkGate {
    private NetworkGate() {}
    public static void check() throws IOException {
        try {
            Properties state = new Properties();
            BufferedReader reader = new BufferedReader(new FileReader(
                    "/data/local/smarttube-gen5w-network/state"));
            try { state.load(reader); } finally { reader.close(); }
            reader = new BufferedReader(new FileReader("/proc/sys/kernel/random/boot_id"));
            String boot;
            try { boot = reader.readLine(); } finally { reader.close(); }
            if (NetworkStateRule.allows(state, Process.myUid(), SystemClock.elapsedRealtime(), boot)) return;
        } catch (Exception unavailable) {
            // Missing, stale, or unreadable service state must never permit fallback.
        }
        throw new IOException("Connect to Wi-Fi and install the full NEMESIS package: network guard not ready");
    }
}
