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
"""
import re
import sys
from pathlib import Path



def patch_get_tasks(root: Path) -> None:
    p = root / "AndroidManifest.xml"
    s = p.read_text(encoding="utf-8")
    if 'android:name="android.permission.GET_TASKS"' in s:
        return
    m = re.search(r"<manifest\b[^>]*>", s)
    if not m:
        raise SystemExit("AndroidManifest.xml: no <manifest> element")
    s = s[: m.end()] + '\n    <uses-permission android:name="android.permission.GET_TASKS"/>' + s[m.end():]
    p.write_text(s, encoding="utf-8")


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


def main() -> None:
    root, code = Path(sys.argv[1]), int(sys.argv[2])
    url = sys.argv[3] if len(sys.argv) > 3 else ""
    patch_get_tasks(root)
    patch_conscrypt(root)
    patch_update_urls(root, url)
    patch_version_code(root, code)
    patch_edge_slide(root)
    print(f"patched: GET_TASKS, Conscrypt, update_urls={url or '(empty: update check off)'}, versionCode={code}, edge-swipe back")


if __name__ == "__main__":
    main()
