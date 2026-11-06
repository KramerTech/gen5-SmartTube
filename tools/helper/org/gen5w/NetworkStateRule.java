package org.gen5w;

import java.util.Properties;

/** No stale state or another app's guard may authorize this app's networking. */
public final class NetworkStateRule {
    private NetworkStateRule() {}
    public static boolean allows(Properties state,int uid,long elapsedMs,String bootId) {
        try {
            double uptime=Double.parseDouble(state.getProperty("uptime","-1"));
            if(Double.isNaN(uptime)||Double.isInfinite(uptime)||uptime<0) return false;
            long checked=(long)(uptime*1000);
            long age=elapsedMs-checked;
            return bootId!=null && !bootId.isEmpty() && bootId.equals(state.getProperty("boot_id")) &&
                    "2".equals(state.getProperty("version")) && "1".equals(state.getProperty("ready")) &&
                    "wlan0".equals(state.getProperty("interface")) &&
                    Integer.parseInt(state.getProperty("uid","-1"))==uid && age>=0 && age<=2500;
        } catch(Exception invalid) { return false; }
    }
}
