"""
بعد از `flutter create` اجرا می‌شود و پوشه‌ی android را برای sing-box آماده می‌کند:
  - کپی فایل‌های Kotlin
  - افزودن مجوزها و سرویس VPN به AndroidManifest.xml
  - تنظیم minSdk و افزودن libbox.aar در Gradle
"""
import pathlib
import re
import shutil

ANDROID = pathlib.Path("android")
APP = ANDROID / "app"

# ---------------------------------------------------------------- Kotlin
kotlin_dir = APP / "src/main/kotlin/com/redvpn/red_vpn"
kotlin_dir.mkdir(parents=True, exist_ok=True)
for name in ("MainActivity.kt", "RedVpnService.kt"):
    shutil.copy(pathlib.Path("android_native") / name, kotlin_dir / name)

# -------------------------------------------------------------- Manifest
manifest = APP / "src/main/AndroidManifest.xml"
text = manifest.read_text(encoding="utf-8")

# اسم برنامه در لانچر گوشی
text = re.sub(r'android:label="[^"]*"', 'android:label="TheVil"', text, count=1)

if "BIND_VPN_SERVICE" not in text:
    permissions = """    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
"""
    service = """        <service
            android:name=".RedVpnService"
            android:exported="false"
            android:foregroundServiceType="systemExempted"
            android:permission="android.permission.BIND_VPN_SERVICE">
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
        </service>
"""
    text = text.replace("<application", permissions + "    <application", 1)
    text = text.replace("</application>", service + "    </application>", 1)

manifest.write_text(text, encoding="utf-8")

# ---------------------------------------------------------------- Gradle
kts = APP / "build.gradle.kts"
groovy = APP / "build.gradle"

if kts.exists():
    g = kts.read_text(encoding="utf-8")
    g = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", g)
    g += '\ndependencies {\n    implementation(files("libs/libbox.aar"))\n}\n'
    kts.write_text(g, encoding="utf-8")
elif groovy.exists():
    g = groovy.read_text(encoding="utf-8")
    g = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", g)
    g += "\ndependencies {\n    implementation files('libs/libbox.aar')\n}\n"
    groovy.write_text(g, encoding="utf-8")
else:
    raise SystemExit("build.gradle(.kts) پیدا نشد")

print("android patched OK")
