"""Apply the Gen5W patches to an apktool-decoded SmartTube tree.

usage: patch.py <decoded dir> <version code> [update manifest url]

Patches (each fails loudly if SmartTube changed underneath it):
  1. GET_TASKS permission: Hyundai's ActivityManager checks it in
     Activity.finish(), so without it the app dies on its splash screen.
  2. NetworkData.isConscryptEnabled() returns true: KitKat's system libssl
     crashes (SIGSEGV in ssl_parse_serverhello_tlsext) and there are no Play
     Services to provide a newer TLS stack; this routes HTTPS through the
     Conscrypt SmartTube already bundles.
  3. update_urls: the in-app update check points at this project's releases
     instead of upstream's (whose APK isn't patched or signed with our key),
     or is emptied (check off) when no URL is given.
  4. versionCode: upstream code * 100 + revision, so each of our revisions is
     an update over the last and over the upstream build of the same version.
  5. Swipe-from-left-edge = Back on Android 4.4: SmartTube already has it
     (MotherActivity.initEdgeSlide, the Slidr library; a finished slide calls
     onBackPressed) but only enables it on API 21+. Its API-21-only call in
     Slidr is version-guarded, so the gate is lowered to API 19.
  6. Edge swipe survives relayouts: Slidr's SliderPanel drags the content with
     offsetLeftAndRight, and any layout pass puts it back at 0. In the player
     the position text relayouts the window every second, so a swipe ends
     with the content at 0 and Slidr treats it as cancelled. SliderPanel gets
     an onLayout that restores the offset while a drag or settle is running.
  7. Driving regulation: Gen5W's com.hkmc.regulation service says when the car
     is out of park, but leaves it to each app to obey (its client-side
     register() is an empty stub). A new class, org.gen5w.DrivingGuard, is
     called from MotherActivity.onCreate (every SmartTube screen): if the car
     is regulated it shows Hyundai's "not available while driving" popup,
     finishes every screen's task (else ActivityManager relaunches them; the
     player has its own task) and kills the process. Otherwise it registers
     for ACTION_ENTER_REGULATION and does the same when the car leaves park
     (popup only if SmartTube was in use). Adds the normal-level
     AUTOMOTIVE_REGULATION permission.
"""
import re
import sys
from pathlib import Path



def add_permission(root: Path, name: str) -> None:
    p = root / "AndroidManifest.xml"
    s = p.read_text(encoding="utf-8")
    if f'android:name="{name}"' in s:
        return
    m = re.search(r"<manifest\b[^>]*>", s)
    if not m:
        raise SystemExit("AndroidManifest.xml: no <manifest> element")
    s = s[: m.end()] + f'\n    <uses-permission android:name="{name}"/>' + s[m.end():]
    p.write_text(s, encoding="utf-8")


def patch_get_tasks(root: Path) -> None:
    add_permission(root, "android.permission.GET_TASKS")


def patch_conscrypt(root: Path) -> None:
    hits = [
        f for d in sorted(root.glob("smali*"))
        for f in d.rglob("NetworkData.smali")
        if f.read_text(encoding="utf-8").startswith(".class public Lcom/liskovsoft/smartyoutubetv2/common/prefs/NetworkData;")
    ]
    if len(hits) != 1:
        raise SystemExit(f"NetworkData.smali: expected 1, found {len(hits)} - SmartTube changed, re-check the Conscrypt patch")
    p = hits[0]
    s = p.read_text(encoding="utf-8")
    pat = re.compile(r"(\.method public isConscryptEnabled\(\)Z\n).*?(\.end method)", re.S)
    if not pat.search(s):
        raise SystemExit("isConscryptEnabled() not found - SmartTube changed, re-check the Conscrypt patch")
    s = pat.sub(r"\1    .locals 1\n\n    const/4 v0, 0x1\n\n    return v0\n\2", s, count=1)
    p.write_text(s, encoding="utf-8")


def patch_update_urls(root: Path, url: str) -> None:
    p = root / "res" / "values" / "arrays.xml"
    s = p.read_text(encoding="utf-8")
    pat = re.compile(r'<string-array name="update_urls">.*?</string-array>|<string-array name="update_urls"\s*/>', re.S)
    if len(pat.findall(s)) != 1:
        raise SystemExit("arrays.xml: update_urls not found exactly once - SmartTube changed, re-check the updater patch")
    items = f"\n        <item>{url}</item>\n    " if url else ""
    s = pat.sub(f'<string-array name="update_urls">{items}</string-array>', s, count=1)
    p.write_text(s, encoding="utf-8")


def patch_version_code(root: Path, code: int) -> None:
    p = root / "apktool.yml"
    s = p.read_text(encoding="utf-8")
    pat = re.compile(r"(versionCode:\s*)'?\d+'?")
    if len(pat.findall(s)) != 1:
        raise SystemExit("apktool.yml: versionCode not found exactly once")
    s = pat.sub(rf"\g<1>{code}", s, count=1)
    p.write_text(s, encoding="utf-8")


def patch_edge_slide(root: Path) -> None:
    hits = [
        f for d in sorted(root.glob("smali*"))
        for f in d.rglob("MotherActivity.smali")
        if f.read_text(encoding="utf-8").startswith(".class public Lcom/liskovsoft/smartyoutubetv2/common/misc/MotherActivity;")
    ]
    if len(hits) != 1:
        raise SystemExit(f"MotherActivity.smali: expected 1, found {len(hits)} - SmartTube changed, re-check the edge-slide patch")
    p = hits[0]
    s = p.read_text(encoding="utf-8")
    m = re.search(r"\.method private initEdgeSlide\(\)V\n.*?\.end method", s, re.S)
    if not m:
        raise SystemExit("initEdgeSlide() not found - SmartTube changed, re-check the edge-slide patch")
    body = m.group(0)
    gate = "    const/16 v1, 0x15\n"
    if body.count(gate) != 1 or "Lcom/r0adkll/slidr/Slidr;->attach" not in body:
        raise SystemExit("initEdgeSlide() no longer looks like an API 21 gate around Slidr.attach - re-check the edge-slide patch")
    s = s.replace(body, body.replace(gate, "    const/16 v1, 0x13\n"), 1)
    p.write_text(s, encoding="utf-8")


SLIDER_ON_LAYOUT = """
.method protected onLayout(ZIIII)V
    .locals 2

    iget-object v0, p0, Lcom/r0adkll/slidr/widget/SliderPanel;->decorView:Landroid/view/View;

    invoke-virtual {v0}, Landroid/view/View;->getLeft()I

    move-result v0

    invoke-super/range {p0 .. p5}, Landroid/widget/FrameLayout;->onLayout(ZIIII)V

    iget-object v1, p0, Lcom/r0adkll/slidr/widget/SliderPanel;->dragHelper:Lcom/r0adkll/slidr/util/ViewDragHelper;

    if-eqz v1, :done

    invoke-virtual {v1}, Lcom/r0adkll/slidr/util/ViewDragHelper;->getViewDragState()I

    move-result v1

    if-eqz v1, :done

    iget-object v1, p0, Lcom/r0adkll/slidr/widget/SliderPanel;->decorView:Landroid/view/View;

    invoke-virtual {v1}, Landroid/view/View;->getLeft()I

    move-result p1

    sub-int/2addr v0, p1

    invoke-virtual {v1, v0}, Landroid/view/View;->offsetLeftAndRight(I)V

    :done
    return-void
.end method
"""


def patch_slider_layout(root: Path) -> None:
    hits = [
        f for d in sorted(root.glob("smali*"))
        for f in d.rglob("SliderPanel.smali")
        if f.read_text(encoding="utf-8").startswith(".class public Lcom/r0adkll/slidr/widget/SliderPanel;")
    ]
    if len(hits) != 1:
        raise SystemExit(f"SliderPanel.smali: expected 1, found {len(hits)} - SmartTube changed, re-check the slider layout patch")
    p = hits[0]
    s = p.read_text(encoding="utf-8")
    needed = (
        ".super Landroid/widget/FrameLayout;",
        ".field private decorView:Landroid/view/View;",
        ".field private dragHelper:Lcom/r0adkll/slidr/util/ViewDragHelper;",
    )
    if not all(n in s for n in needed) or " onLayout(ZIIII)V" in s:
        raise SystemExit("SliderPanel no longer looks like Slidr's FrameLayout without an onLayout - re-check the slider layout patch")
    p.write_text(s.rstrip("\n") + "\n" + SLIDER_ON_LAYOUT, encoding="utf-8")


# In the main dex next to MotherActivity: on KitKat (legacy multidex) classes
# that run this early must be there. Keep it lean, the main dex is nearly full.
DRIVING_GUARD = """.class public Lorg/gen5w/DrivingGuard;
.super Landroid/content/BroadcastReceiver;
.source "DrivingGuard.java"


# WeakReferences to every screen created: the player runs in its own task,
# so finishing one task would leave another for ActivityManager to relaunch.
.field private static final sActivities:Ljava/util/ArrayList;

.field private static sReceiver:Lorg/gen5w/DrivingGuard;


.method static constructor <clinit>()V
    .locals 1

    new-instance v0, Ljava/util/ArrayList;

    invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V

    sput-object v0, Lorg/gen5w/DrivingGuard;->sActivities:Ljava/util/ArrayList;

    return-void
.end method

.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Landroid/content/BroadcastReceiver;-><init>()V

    return-void
.end method

.method private static manager()Lcom/hkmc/regulation/IRegulationManager;
    .locals 1

    const-string v0, "com.hkmc.regulation"

    invoke-static {v0}, Landroid/os/ServiceManager;->getService(Ljava/lang/String;)Landroid/os/IBinder;

    move-result-object v0

    invoke-static {v0}, Lcom/hkmc/regulation/IRegulationManager$Stub;->asInterface(Landroid/os/IBinder;)Lcom/hkmc/regulation/IRegulationManager;

    move-result-object v0

    return-object v0
.end method

# Optionally show Hyundai's own regulation popup (drawn by the system, so it
# outlives us), finish every screen's task so ActivityManager has nothing to
# relaunch, then kill this process.
.method private static stop(Z)V
    .locals 4

    if-eqz p0, :finish

    :try_start_0
    invoke-static {}, Lorg/gen5w/DrivingGuard;->manager()Lcom/hkmc/regulation/IRegulationManager;

    move-result-object v0

    const-string v1, "SmartTube is not available while driving"

    const-string v2, "org.smarttube.stable"

    invoke-interface {v0, v1, v2}, Lcom/hkmc/regulation/IRegulationManager;->showRegulationPopup(Ljava/lang/String;Ljava/lang/String;)V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :finish

    :finish
    sget-object v1, Lorg/gen5w/DrivingGuard;->sActivities:Ljava/util/ArrayList;

    invoke-virtual {v1}, Ljava/util/ArrayList;->size()I

    move-result v2

    :next
    if-eqz v2, :kill

    add-int/lit8 v2, v2, -0x1

    :try_start_1
    invoke-virtual {v1, v2}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;

    move-result-object v0

    check-cast v0, Ljava/lang/ref/WeakReference;

    invoke-virtual {v0}, Ljava/lang/ref/WeakReference;->get()Ljava/lang/Object;

    move-result-object v0

    check-cast v0, Landroid/app/Activity;

    if-eqz v0, :next

    invoke-virtual {v0}, Landroid/app/Activity;->finishAffinity()V
    :try_end_1
    .catch Ljava/lang/Throwable; {:try_start_1 .. :try_end_1} :next

    goto :next

    :kill
    invoke-static {}, Landroid/os/Process;->myPid()I

    move-result v0

    invoke-static {v0}, Landroid/os/Process;->killProcess(I)V

    return-void
.end method

# From MotherActivity.onCreate. Does nothing where there's no regulation service.
.method public static onCreate(Landroid/app/Activity;)V
    .locals 3

    sget-object v0, Lorg/gen5w/DrivingGuard;->sActivities:Ljava/util/ArrayList;

    new-instance v1, Ljava/lang/ref/WeakReference;

    invoke-direct {v1, p0}, Ljava/lang/ref/WeakReference;-><init>(Ljava/lang/Object;)V

    invoke-virtual {v0, v1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z

    :try_start_0
    invoke-static {}, Lorg/gen5w/DrivingGuard;->manager()Lcom/hkmc/regulation/IRegulationManager;

    move-result-object v0

    if-eqz v0, :done

    invoke-interface {v0}, Lcom/hkmc/regulation/IRegulationManager;->getStatus()I

    move-result v0

    if-eqz v0, :parked

    const/4 v0, 0x1

    invoke-static {v0}, Lorg/gen5w/DrivingGuard;->stop(Z)V

    :parked
    sget-object v0, Lorg/gen5w/DrivingGuard;->sReceiver:Lorg/gen5w/DrivingGuard;

    if-nez v0, :done

    new-instance v0, Lorg/gen5w/DrivingGuard;

    invoke-direct {v0}, Lorg/gen5w/DrivingGuard;-><init>()V

    sput-object v0, Lorg/gen5w/DrivingGuard;->sReceiver:Lorg/gen5w/DrivingGuard;

    new-instance v1, Landroid/content/IntentFilter;

    const-string v2, "android.mobis.regulation.ACTION_ENTER_REGULATION"

    invoke-direct {v1, v2}, Landroid/content/IntentFilter;-><init>(Ljava/lang/String;)V

    invoke-virtual {p0}, Landroid/app/Activity;->getApplicationContext()Landroid/content/Context;

    move-result-object v2

    invoke-virtual {v2, v0, v1}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;)Landroid/content/Intent;
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :done

    :done
    return-void
.end method

# The car left park. Explain with the popup only if SmartTube was in use
# (foreground, visible or playing), not when it was just cached.
.method public onReceive(Landroid/content/Context;Landroid/content/Intent;)V
    .locals 2

    new-instance v0, Landroid/app/ActivityManager$RunningAppProcessInfo;

    invoke-direct {v0}, Landroid/app/ActivityManager$RunningAppProcessInfo;-><init>()V

    invoke-static {v0}, Landroid/app/ActivityManager;->getMyMemoryState(Landroid/app/ActivityManager$RunningAppProcessInfo;)V

    iget v0, v0, Landroid/app/ActivityManager$RunningAppProcessInfo;->importance:I

    const/16 v1, 0x12c

    if-ge v0, v1, :quiet

    const/4 v1, 0x1

    goto :stop

    :quiet
    const/4 v1, 0x0

    :stop
    invoke-static {v1}, Lorg/gen5w/DrivingGuard;->stop(Z)V

    return-void
.end method
"""


def patch_driving_guard(root: Path) -> None:
    hits = [
        f for d in sorted(root.glob("smali*"))
        for f in d.rglob("MotherActivity.smali")
        if f.read_text(encoding="utf-8").startswith(".class public Lcom/liskovsoft/smartyoutubetv2/common/misc/MotherActivity;")
    ]
    if len(hits) != 1:
        raise SystemExit(f"MotherActivity.smali: expected 1, found {len(hits)} - SmartTube changed, re-check the driving guard patch")
    p = hits[0]
    s = p.read_text(encoding="utf-8")
    m = re.search(r"\.method protected onCreate\(Landroid/os/Bundle;\)V\n.*?\.end method", s, re.S)
    sup = "    invoke-super {p0, p1}, Landroidx/fragment/app/FragmentActivity;->onCreate(Landroid/os/Bundle;)V\n"
    if not m or m.group(0).count(sup) != 1:
        raise SystemExit("MotherActivity.onCreate() no longer calls FragmentActivity.onCreate once - re-check the driving guard patch")
    body = m.group(0)
    hook = sup + "\n    invoke-static {p0}, Lorg/gen5w/DrivingGuard;->onCreate(Landroid/app/Activity;)V\n"
    s = s.replace(body, body.replace(sup, hook), 1)
    p.write_text(s, encoding="utf-8")

    dex_dir = next(d for d in root.glob("smali*") if p.is_relative_to(d))
    guard = dex_dir / "org" / "gen5w" / "DrivingGuard.smali"
    guard.parent.mkdir(parents=True)
    guard.write_text(DRIVING_GUARD, encoding="utf-8")
    add_permission(root, "com.hkmc.permission.AUTOMOTIVE_REGULATION")


def main() -> None:
    root, code = Path(sys.argv[1]), int(sys.argv[2])
    url = sys.argv[3] if len(sys.argv) > 3 else ""
    patch_get_tasks(root)
    patch_conscrypt(root)
    patch_update_urls(root, url)
    patch_version_code(root, code)
    patch_edge_slide(root)
    patch_slider_layout(root)
    patch_driving_guard(root)
    print(f"patched: GET_TASKS, Conscrypt, update_urls={url or '(empty: update check off)'}, versionCode={code}, edge-swipe back (+ relayout fix), driving guard")


if __name__ == "__main__":
    main()
