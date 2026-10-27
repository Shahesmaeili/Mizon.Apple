# Mizon.Apple

اپلیکیشن نیتیو **Mizon** برای مک، آیفون و اپل واچ، با SwiftUI و Liquid Glass واقعی اپل. این مرحله بر **صفحه‌های ورود و ساخت حساب مک** تمرکز دارد و از پکیج [Mizon.API.Swift](https://github.com/Shahesmaeili/Mizon.API.Swift) استفاده می‌کند.

![Mac login](Documentation/Screenshots/login-macos.jpg)

## اجرا روی مک

پروژهٔ `Mizon.xcodeproj` را در Xcode 27 یا جدیدتر باز کنید. Scheme **Mizon** و مقصد **My Mac** را انتخاب و Run کنید. برای اجرای روی دستگاه شخصی، Signing Team خودتان را انتخاب کنید.

ساخت یک بستهٔ محلی بدون وابستگی به ابزارهای جانبی:

```sh
./Scripts/build-macos.sh
open build/Mizon.app
```

Swift 6.4+ و macOS 26+ لازم است. SDKهای iOS و watchOS در Xcode ارائه می‌شوند. خروجی محلی ad-hoc امضا می‌شود؛ انتشار خارج از دستگاه توسعه به امضای توسعه‌دهنده و فرایند معمول توزیع اپل نیاز دارد.

## ورود

- ایمیل یا نام کاربری و رمز عبور، مطابق کلاینت ویندوز.
- تشخیص ایمیل دقیقاً با الگوی `LoginPageViewModel.IsEmail` ویندوز؛ فاصلهٔ ابتدا و انتهای شناسه حذف می‌شود و رمز دست‌نخورده می‌ماند.
- درخواست واقعی `LoginOperation` از SDK، با gzip و قرارداد پاسخ اصلی.
- دکمهٔ ورود تا تکمیل فیلدها غیرفعال است؛ هنگام ارسال، فرم قفل می‌شود و حلقهٔ انتظار روی کارت دوم، مطابق مرجع نمایش داده می‌شود.
- فیلد امن رمز، ارسال با Enter و نمایش خطای فارسی اتصال.
- توکن‌های نشست فقط در **Keychain همین دستگاه** و جداگانه برای هر آدرس سرویس ذخیره می‌شوند. رمز عبور ذخیره یا لاگ نمی‌شود و پس از ورود موفق از فرم پاک می‌شود.

پیش‌فرض سرور مانند مرجع `https://localhost:5128` است. از منوی **Mizon → Settings** آدرس HTTPS سرویس واقعی خودتان را وارد کنید. آیفون و ساعت به آدرس قابل‌دسترسی از همان دستگاه نیاز دارند؛ `localhost` به خود دستگاه اشاره می‌کند. اعتبارسنجی TLS غیرفعال نشده است.

آدرس بک‌اند فعال یا حساب آزمایشی در اختیار پروژه نیست؛ ورود موفق از طریق پاسخ‌های کنترل‌شدهٔ تست بررسی شده و خطای اتصال واقعی به localhost در اپ مک نیز آزمایش شده است. آزمون ورود به سرویس زنده همچنان به آدرس و حساب شما نیاز دارد.

## طراحی و مرجع ویندوز

مرجع: [Mizon.Windows](https://github.com/Shahesmaeili/Mizon.Windows) در کامیت `eb809c142c38c4d6cb88a1d75b83dbd61680c351`، به‌ویژه:

- `Pages/LoginPage.xaml`
- `ViewModels/LoginPageViewModel.cs`
- `Assets/Animation.gif` و لوگوی هدفون

متن‌ها، فونت **IRANSans**، آیکون‌های همان **FluentIcons.WinUI / Seagull Fluent Icons**، فایل GIF اصلی، فاصله‌ها و اندازه‌های کارت از XAML منتقل شده‌اند. کارت ورود ۳۰۴×۴۴۰ و کارت ساخت حساب ۳۰۴×۵۰۰ است؛ padding برابر ۲۸، فیلدها ۲۴۰ و گوشهٔ کارت ۸ است. هر دو روی کارت دقیقاً متن‌های «ورود» و «حساب ندارم» را از مرجع دارند. حالت اولیه نیز مطابق `IsFlipped=True`، ساخت حساب است.

کنترل‌های ستاره و چرخش از [سورس DevWinUI](https://github.com/Ghost1372/DevWinUI) به Swift ترجمه شده‌اند: ۱۰۰۲ ستارهٔ کوچک و ۱۰۰۱ بزرگ، بافت اصلی CircleMask، دامنه‌ها و زمان‌های حرکت و opacity، بازتولید تصادفی با سقف پنج بار، شروع ۱۶۰۰ میلی‌ثانیه‌ای و جابه‌جایی تجمعی سه‌بعدی؛ چرخش حول Y با دورهٔ فنر ۲۰۰ میلی‌ثانیه، میرایی ۰٫۵، perspective متناسب با عرض و پنهان‌سازی روی پشت بر اساس زاویه. شیشهٔ تمام پنجره با `NSVisualEffectView` و blending پشت پنجره اجرا می‌شود و کارت‌ها Liquid Glass نیتیو دارند. رنگ و rasterization متریال‌های نیتیو macOS طبعاً با WinUI یکسان نیست. Reduce Motion حرکت‌ها را متوقف می‌کند.

![Mac registration](Documentation/Screenshots/registration-macos.jpg)

## دامنهٔ این مرحله

**پیاده‌سازی شده:** دو روی کارت ورود/ساخت حساب مک، اتصال به SDK، ذخیرهٔ امن نشست، وضعیت موفقیت و خطا، تنظیمات سرویس و تست‌ها.

**زیرساخت پلتفرم‌ها:** Target مشترک **Mizon** برای macOS/iOS و Target مستقل **MizonWatch** برای watchOS. نمای ساعت فشرده است؛ بیلد هر سه Target بررسی شده، اما پرداخت بصری و آزمون دستگاه آیفون و ساعت به مراحل بعد تعلق دارد.

رابط ساخت حساب و چرخش آن پیاده‌سازی شده‌اند. در سورس ویندوز، دکمهٔ هر دو روی کارت همان LoginCommand را صدا می‌زند و SDK endpoint ثبت‌نام ندارد؛ این رفتار عیناً حفظ شده است. صفحهٔ اصلی هنوز خارج از دامنهٔ این مرحله است. پس از ورود، تأیید نشست نمایش داده می‌شود؛ «بازگشت به ورود» فقط نشست همین دستگاه را پاک می‌کند و ادعای خروج از تمام دستگاه‌ها ندارد.

## ساختار

```text
App/                         Native Xcode entry points, app icon and bundle metadata
Sources/MizonAppleCore/
  Models/                    Backend configuration, session and errors
  Services/                  SDK authentication and Keychain session store
  ViewModels/                Observable login state
Sources/MizonAppleUI/
  Pages/                     Login, server settings and compact watch view
  Components/                Native glass surfaces and animated branding
  Resources/                 Referenced Windows brand assets
Tests/                       Login state and real SDK contract integration tests
Scripts/                     Build and platform validation
Documentation/               Scope, QA and asset provenance
Mizon.xcodeproj/              Shared macOS/iOS and watchOS schemes
```

## تست و بیلد

```sh
swift test
./Scripts/validate-apple.sh

xcodebuild -project Mizon.xcodeproj -scheme Mizon \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Mizon.xcodeproj -scheme Mizon \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Mizon.xcodeproj -scheme MizonWatch \
  -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build
```

۱۴ تست واحد، رابط و integration برای تشخیص شناسه، اعتبارسنجی سرور، جلوگیری از ارسال دوباره، لغو، پاک‌کردن رمز، پیام خطا، درخواست واقعی SDK و شکست ذخیرهٔ امن وجود دارد. تست‌ها از رمز یا Keychain شخصی استفاده نمی‌کنند. برای جزئیات بررسی دستی، [QA](Documentation/QA.md) را ببینید.

پکیج SDK روی branch `main` تعریف شده و commit حل‌شده در `Package.resolved` ثبت می‌شود. برای دریافت اصلاحات بعدی SDK، در Xcode گزینهٔ **Update to Latest Package Versions** یا `swift package update` را اجرا کنید.
