import java.io.File;
import java.nio.file.Files;
import java.nio.file.Paths;
import com.android.tools.smali.baksmali.Baksmali;
import com.android.tools.smali.baksmali.BaksmaliOptions;
import com.android.tools.smali.dexlib2.Opcodes;
import com.android.tools.smali.dexlib2.dexbacked.DexBackedDexFile;

/** apktool 2.12.0 bundles a trimmed baksmali library without its CLI main(). */
public final class DisassembleHelper {
    public static void main(String[] args) throws Exception {
        DexBackedDexFile dex = new DexBackedDexFile(new Opcodes(19, -1),
                Files.readAllBytes(Paths.get(args[0])), 0);
        BaksmaliOptions options = new BaksmaliOptions();
        options.localsDirective = true;
        options.debugInfo = true;
        Baksmali.disassembleDexFile(dex, new File(args[1]), 1, options);
        if (!new File(args[1], "org/gen5w/ForegroundAudio.smali").isFile())
            throw new IllegalStateException("helper disassembly failed");
    }
}
