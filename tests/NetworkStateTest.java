import java.util.Properties;
import org.gen5w.NetworkStateRule;

public final class NetworkStateTest {
    static Properties valid() {
        Properties p=new Properties();p.setProperty("version","2");p.setProperty("boot_id","test-boot");p.setProperty("ready","1");
        p.setProperty("interface","wlan0");p.setProperty("uid","10209");p.setProperty("uptime","10.0");return p;
    }
    static void check(boolean b) { if(!b)throw new AssertionError(); }
    public static void main(String[] args) {
        check(NetworkStateRule.allows(valid(),10209,10000,"test-boot"));
        check(NetworkStateRule.allows(valid(),10209,12500,"test-boot"));
        check(!NetworkStateRule.allows(valid(),10209,12501,"test-boot"));
        check(!NetworkStateRule.allows(valid(),10209,9999,"test-boot"));
        check(!NetworkStateRule.allows(valid(),10210,10000,"test-boot"));
        check(!NetworkStateRule.allows(new Properties(),10209,10000,"test-boot"));
        for(String key:new String[]{"version","boot_id","ready","interface","uid","uptime"}) {
            Properties p=valid();p.setProperty(key,"invalid");check(!NetworkStateRule.allows(p,10209,10000,"test-boot"));
        }
        for(String iface:new String[]{"rmnet0","rmnet2","eth0","lo"}) {
            Properties p=valid();p.setProperty("interface",iface);check(!NetworkStateRule.allows(p,10209,10000,"test-boot"));
        }
        for(String stamp:new String[]{"NaN","Infinity","-1"}) {
            Properties p=valid();p.setProperty("uptime",stamp);check(!NetworkStateRule.allows(p,10209,10000,"test-boot"));
        }
        check(!NetworkStateRule.allows(valid(),10209,10000,"another-boot"));
        System.out.println("PASS reboot/fresh/stale, wrong UID, malformed and unapproved-interface network states");
    }
}
