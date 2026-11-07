# TheVil — کلاینت پروکسی با تم مشکی و قرمز

اسکلت Flutter برای ساخت اپی شبیه V2Box.

## وضعیت فعلی
- تم مشکی‌قرمز و رابط فارسی (RTL)
- صفحه‌ی خانه با دکمه‌ی اتصال متحرک
- لیست سرورها: افزودن از کلیپ‌بورد، انتخاب، حذف با کشیدن، تست پینگ
- پارسر لینک‌های `vmess://` `vless://` `trojan://` `ss://` و محتوای اشتراک (base64)
- اتصال فعلاً **شبیه‌سازی** است تا هسته‌ی نیتیو وصل شود

## راه‌اندازی
1. نصب Flutter (نسخه 3.19 به بالا)
2. داخل پوشه‌ی پروژه، یک‌بار برای ساخت پوشه‌های android و ios:
   ```
   flutter create . --project-name red_vpn --org com.yourname
   ```
   (فایل‌های `lib/` و `pubspec.yaml` دست نمی‌خورند)
3. `flutter pub get`
4. `flutter run`

## قدم بعدی: اتصال واقعی (اندروید)
در `MainActivity.kt` یک `MethodChannel` با نام `red_vpn/core` بسازید:
- `start(link)` ← لینک را به کانفیگ Xray/sing-box تبدیل کند، `VpnService` را بالا بیاورد و هسته را اجرا کند
- `stop()` ← هسته و VpnService را متوقف کند

هسته‌های پیشنهادی (متن‌باز): **sing-box** (کتابخانه‌ی `libbox`) یا **Xray-core** (`AndroidLibXrayLite`).

## iOS
نیاز به Network Extension و حساب Apple Developer پولی دارد. کانال همان `red_vpn/core` است.

## کارهای بعدی پیشنهادی
- اسکن QR (پکیج `mobile_scanner` در pubspec هست)
- افزودن اشتراک با URL و به‌روزرسانی خودکار
- Per-app proxy و تنظیمات DNS
- نمایش سرعت و حجم مصرفی
