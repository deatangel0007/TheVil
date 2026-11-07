# اتصال sing-box در اندروید

## ۱) ساخت libbox.aar
هسته‌ی sing-box برای اندروید از کتابخانه‌ی `libbox` استفاده می‌کند که باید خودتان از سورس بسازید
(نیاز: Go، Android SDK + NDK، و gomobile مخصوص sing-box).

1. سورس رسمی را بگیرید و روی یک تگ 1.12.x بروید (کانفیگ‌هایی که `singbox_config.dart` می‌سازد برای 1.12 است):
   `git clone https://github.com/SagerNet/sing-box && cd sing-box && git checkout v1.12.x`
2. طبق بخش «build libbox / Android» مستندات رسمی sing-box، فایل `libbox.aar` را بسازید.
   (معمولاً با `make lib_android` یا ابزار `build_libbox -target android` و تگ‌های
   `with_gvisor,with_quic,with_utls` انجام می‌شود؛ دستور دقیق را از مستندات همان نسخه بردارید.)
3. فایل خروجی را در `android/app/libs/libbox.aar` بگذارید.

## ۲) آماده‌سازی پروژه
```
flutter create . --project-name red_vpn --org com.redvpn
```
پکیج اپ می‌شود `com.redvpn.red_vpn` (همان که در فایل‌های Kotlin نوشته شده).

## ۳) کپی فایل‌ها
- `android_native/MainActivity.kt` و `android_native/RedVpnService.kt`
  را روی/کنار `android/app/src/main/kotlin/com/redvpn/red_vpn/` بگذارید (MainActivity.kt قبلی را جایگزین کنید).
- محتوای `android_native/manifest_additions.xml` را در `AndroidManifest.xml` اضافه کنید.

## ۴) Gradle (`android/app/build.gradle.kts`)
```kotlin
dependencies {
    implementation(files("libs/libbox.aar"))
}
```
و `minSdk` را حداقل 23 بگذارید:
```kotlin
defaultConfig { minSdk = 23 }
```

## ۵) اجرا
`flutter pub get && flutter run` روی گوشی واقعی (امولیتور برای VPN مناسب نیست).
با اولین اتصال، اندروید مجوز VPN را می‌پرسد.

## اگر کامپایل خطا داد
احتمال‌ش بیشتر در `RedVpnService.kt` است، چون امضای متدهای `PlatformInterface`
(مثلاً `updateDefaultInterface` یا `NetworkInterfaceIterator`) بین نسخه‌ها فرق می‌کند.
متن خطا را برای من بفرست تا اصلاحش کنم.

## محدودیت‌های فعلی
- Per-app proxy پشتیبانی نمی‌شود (`findConnectionOwner` خطا می‌دهد).
- پایش تغییر شبکه (وای‌فای ↔ دیتا) فقط یک‌بار هنگام اتصال انجام می‌شود.
