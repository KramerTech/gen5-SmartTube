"""Host tests of the real helper Java, using deterministic Android lifecycle doubles.

Run: python3 -m unittest discover -s tests -v (JDK required).
The APK build separately compiles against android.jar and assembles the real dex.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import importlib.util

ROOT = Path(__file__).resolve().parents[1]

STUBS = {
    "android/os/Looper.java": """package android.os;
      public class Looper { public static Looper getMainLooper(){ return new Looper(); } }""",
    "android/os/Handler.java": """package android.os; import java.util.*;
      public class Handler {
        static final List<Runnable> pending=new ArrayList<Runnable>();
        public Handler(Looper l){} public void removeCallbacks(Runnable r){pending.remove(r);}
        public boolean postDelayed(Runnable r,long ms){if(ms!=700)throw new AssertionError();pending.add(r);return true;}
        public static void drain(){for(Runnable r:new ArrayList<Runnable>(pending)){pending.remove(r);r.run();}}
      }""",
    "android/content/Context.java": """package android.content;
      public class Context { public static final int MODE_PRIVATE=0; }""",
    "android/app/Activity.java": """package android.app;
      public class Activity extends android.content.Context {
        public Prefs getSharedPreferences(String n,int m){return new Prefs();}
        public static class Prefs {
          public boolean getBoolean(String k,boolean d){return true;}
          public Prefs edit(){return this;} public Prefs putBoolean(String k,boolean v){return this;}
          public void apply(){}
        }
      }""",
    "android/app/AlertDialog.java": """package android.app;
      public class AlertDialog { public static class Builder {
        public Builder(Activity a){} public Builder setTitle(String s){return this;}
        public Builder setMessage(String s){return this;}
        public Builder setPositiveButton(int i,Object x){return this;} public void show(){}
      }}""",
    "android/R.java": "package android; public class R {public static class string {public static final int ok=1;}}",
    "android/media/AudioManager.java": """package android.media;
      public class AudioManager {
        public interface OnAudioFocusChangeListener {void onAudioFocusChange(int c);}
        public static final int AUDIOFOCUS_LOSS=-1,AUDIOFOCUS_GAIN_TRANSIENT=2,AUDIOFOCUS_REQUEST_GRANTED=1;
        public int requests,abandons,result=1; public OnAudioFocusChangeListener proxy;
        public int requestAudioFocus(OnAudioFocusChangeListener l,int s,int g){
          if(g!=2)throw new AssertionError("must use standard transient focus"); requests++;proxy=l;return result;}
        public int abandonAudioFocus(OnAudioFocusChangeListener l){abandons++;return 1;}
      }""",
}

TEST = """import android.app.Activity; import android.os.Handler;
import android.media.AudioManager; import org.gen5w.ForegroundAudio;
public class AudioTest {
 static void check(boolean b){if(!b)throw new AssertionError();}
 static class Listener implements AudioManager.OnAudioFocusChangeListener {
   int calls,last; public void onAudioFocusChange(int c){calls++;last=c;}
 }
 public static void main(String[] args){
   AudioManager m=new AudioManager(); Activity player=new Activity(),browse=new Activity();
   Listener first=new Listener(),second=new Listener();
   ForegroundAudio.onResume(browse); Handler.drain();check(m.requests==0); // idle must not acquire focus
   ForegroundAudio.onPause(browse); ForegroundAudio.onResume(player);
   check(ForegroundAudio.request(m,first,3,1)==1);check(m.requests==1);
   ForegroundAudio.onPause(player); ForegroundAudio.abandon(m,first);
   ForegroundAudio.onResume(browse); Handler.drain();check(m.abandons==0); // Back does not resume radio
   m.proxy.onAudioFocusChange(1);check(first.calls==0); // released player cannot restart
   ForegroundAudio.request(m,second,3,1);m.proxy.onAudioFocusChange(-2);
   check(second.calls==1 && second.last==-2); // active player still receives interruption
   m.result=0;check(ForegroundAudio.request(m,first,3,1)==0);
   m.proxy.onAudioFocusChange(-3);check(second.calls==2); // denied request preserves current delegate
   m.proxy.onAudioFocusChange(-1);check(second.calls==3);
   int requests=m.requests;ForegroundAudio.onResume(browse);Handler.drain();check(m.requests==requests);
   m.result=1;ForegroundAudio.request(m,second,3,1);
   ForegroundAudio.onPause(browse);Handler.drain();check(m.abandons==1 && second.last==-1);
   ForegroundAudio.onResume(browse);Handler.drain();check(m.requests==requests+1); // no automatic reacquire
   System.out.println("PASS audio lifecycle, Back, interruption, failed request and app exit");
 }
}
"""


class HelperTests(unittest.TestCase):
    def test_audio_lifecycle(self):
        self.assertIsNotNone(shutil.which("javac"), "JDK required")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name, content in STUBS.items():
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(content)
            (root / "AudioTest.java").write_text(TEST)
            sources = [str(p) for p in root.rglob("*.java")]
            sources.append(str(ROOT / "tools/helper/org/gen5w/ForegroundAudio.java"))
            subprocess.run(["javac", "-d", tmp, *sources], check=True)
            subprocess.run(["java", "-cp", tmp, "AudioTest"], check=True)

    def test_patch_hooks_fail_on_changed_upstream(self):
        spec = importlib.util.spec_from_file_location("smarttube_patch", ROOT / "tools/patch.py")
        patch = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(patch)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "smali"
            source.mkdir()
            methods = {
                "MotherActivity": ["protected onResume()V", "protected onPause()V"],
                "RealCall": ["getResponseWithInterceptorChain()Lokhttp3/Response;"],
                "DefaultHttpDataSource": ["public open(Lcom/google/android/exoplayer2/upstream/DataSpec;)J"],
            }
            for name, signatures in methods.items():
                (source / (name + ".smali")).write_text("".join(
                    ".method " + signature + "\n    .locals 2\n    return-void\n.end method\n"
                    for signature in signatures))
            (source / "AudioFocusManager.smali").write_text(
                "invoke-virtual {v0, v1, v2, v3}, Landroid/media/AudioManager;->requestAudioFocus(Landroid/media/AudioManager$OnAudioFocusChangeListener;II)I\n"
                "invoke-virtual {v0, v1}, Landroid/media/AudioManager;->abandonAudioFocus(Landroid/media/AudioManager$OnAudioFocusChangeListener;)I\n")
            patch.patch_wifi_audio(root)
            self.assertIn("ForegroundAudio;->onResume", (source / "MotherActivity.smali").read_text())
            with self.assertRaises(SystemExit):
                patch.patch_wifi_audio(root)  # never silently double-patch a release
            (source / "MotherActivity.smali").write_text(".class Lchanged;\n")
            with self.assertRaises(SystemExit):
                patch.patch_wifi_audio(root)

    def test_network_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["javac", "-d", tmp,
                            str(ROOT / "tools/helper/org/gen5w/NetworkStateRule.java"),
                            str(ROOT / "tests/NetworkStateTest.java")], check=True)
            subprocess.run(["java", "-cp", tmp, "NetworkStateTest"], check=True)


if __name__ == "__main__":
    unittest.main()
