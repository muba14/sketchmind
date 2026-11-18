#!/usr/bin/env python3
"""`flutter create .` sonrasında çalıştır: parmak izi, kamera ve galeri izinlerini ekler.

    python3 tool/setup_platforms.py
"""
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent
changed = []

# --- Android: local_auth, FlutterFragmentActivity ister
for main in (root / "android/app/src/main").rglob("MainActivity.kt"):
    src = main.read_text()
    if "FlutterFragmentActivity" not in src:
        src = src.replace("import io.flutter.embedding.android.FlutterActivity",
                          "import io.flutter.embedding.android.FlutterFragmentActivity")
        src = re.sub(r":\s*FlutterActivity\(\)", ": FlutterFragmentActivity()", src)
        main.write_text(src)
        changed.append(str(main.relative_to(root)))

manifest = root / "android/app/src/main/AndroidManifest.xml"
if manifest.exists():
    src = manifest.read_text()
    if "USE_BIOMETRIC" not in src:
        src = src.replace("<application",
                          '<uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n    <application', 1)
        manifest.write_text(src)
        changed.append(str(manifest.relative_to(root)))

# --- Android: en düşük sürüm 24 (Android 7). Parmak izi/PDF eklentileri eski sürümleri desteklemiyor.
for name in ("build.gradle.kts", "build.gradle"):
    gradle = root / "android/app" / name
    if gradle.exists():
        src = gradle.read_text()
        new = src.replace("flutter.minSdkVersion", "24")
        if new != src:
            gradle.write_text(new)
            changed.append(str(gradle.relative_to(root)))

# --- iOS: izin açıklamaları
plist = root / "ios/Runner/Info.plist"
if plist.exists():
    src = plist.read_text()
    keys = {
        "NSFaceIDUsageDescription": "Kilitli notları açmak için Face ID kullanılır.",
        "NSCameraUsageDescription": "Notlara fotoğraf eklemek için kamera kullanılır.",
        "NSPhotoLibraryUsageDescription": "Notlara galeriden fotoğraf eklemek için.",
    }
    add = "".join(f"\t<key>{k}</key>\n\t<string>{v}</string>\n" for k, v in keys.items() if k not in src)
    if add:
        i = src.rindex("</dict>")
        plist.write_text(src[:i] + add + src[i:])
        changed.append(str(plist.relative_to(root)))

print("Güncellendi:" if changed else "Zaten ayarlı.", *changed, sep="\n  ")
