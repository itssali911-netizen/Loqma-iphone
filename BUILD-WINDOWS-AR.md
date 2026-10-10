# بناء لُقمة من ويندوز

**نجح البناء رقم ٢٤ وخرج ملف التحديث للآيفون.** [نتيجة البناء](https://github.com/itssali911-netizen/Loqma-iphone/actions/runs/38027199614) من المصدر `d7055a1a85780911c395033e77dcb48155753828`: نجحت ٢٦ حالة اختبار Swift و١٦ اختبار أدوات البناء، ثم تجميع نسخة الآيفون وفحص النموذجين لتحليل الصور على Mac. تم التحقق من هوية IPA وبصمته ومحتوياته. الملف جاهز لإعادة التوقيع الشخصي والتجربة على جهازك؛ تفعيل صحتي وحل الإغلاق السابق فعليًا يحتاجان التحقق على الآيفون. التفاصيل في `VALIDATION.md`.

حمّل `Luqma-sideload-24` من Artifacts وفك الضغط. الملف المطلوب هو `Luqma-Sideload.ipa`، ويحتاج إعادة توقيع لحساب Apple وجهازك. نسخته ١٫٢، بناء ٢٤، حجمه 16,422,563 بايت، وبصمة SHA-256 هي `a986cb02cb5cb8bfd943bb3ce55c2540a27da2c8c36530ec7735ff2c4fa372d8`. لتفعيل الربط المباشر بصحتي على ويندوز، اتبع [دليل ربط صحتي](HEALTH-SETUP-AR.md) ومسار Impactor المقترح مع حفظ حساب Apple ومعرّف التطبيق المثبت. نجاح هذا المسار على حسابك يحتاج تحققًا بعد التثبيت. خطوات AltStore أدناه تخص التثبيت العام؛ إن أسقطت أداة التوقيع صلاحيات HealthKit فلن تعمل القراءة المباشرة.

## بناء نسخة جديدة أو رفع نسخة مستقلة

مستودع المشروع العام هو [Loqma-iphone](https://github.com/itssali911-netizen/Loqma-iphone). رفع المصدر إلى الفرع `main` يبدأ مهمة `sideload` تلقائيًا. راجع **Actions** لنتيجة البناء الفعلية. لا يلزم إدخال بيانات Apple في GitHub لهذا المسار. إذا أردت نسخة مستقلة من المصدر، يمكنك إنشاء مستودعك الخاص أو استخدام بديل الرفع التالي.

وللتنفيذ بنفسك من ويندوز:

1. فك ضغط الحزمة. ثبّت [Git for Windows](https://git-scm.com/download/win) و[GitHub CLI](https://cli.github.com/).
2. افتح PowerShell داخل مجلد `Luqma-iPhone`، وشغّل:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\Scripts\upload_github.ps1
   ```

3. سجّل الدخول إلى GitHub في نافذة المتصفح التي يفتحها الأمر. ينشئ السكربت مستودعًا خاصًا باسم `luqma-iphone` ويرفع المصدر؛ الرفع يبدأ مهمة **sideload**. استخدم هذا البديل إذا لم تُنشئ المستودع في المتصفح. إذا كان الاسم مستخدمًا، اختر اسمًا آخر باستخدام `-RepositoryName luqma-iphone-app`.
4. من المستودع افتح **Actions → Luqma iPhone build** وانتظر النتيجة. المهمة تشغّل اختبارات الحسابات وملفات البناء، ثم تبني نسخة جهاز iOS وتجهز ملف IPA لإعادة التوقيع الشخصي.
5. عند نجاح المهمة حمّل **Luqma-sideload-رقم البناء** من **Artifacts** وفك الضغط. الناتج المطلوب `Luqma-Sideload.ipa`. الملف لا يحتوي توقيع حساب Apple؛ AltStore يعيد توقيعه لحسابك وجهازك. نجاح البناء وحده لا يثبت عمل الكاميرا أو صحتي أو تعرف الصور على جهاز فعلي.

المهمة تبدأ عند تعديل ملفات التطبيق أو البناء على `main`، ويمكن تشغيلها يدويًا واختيار الوضع. تحتفظ بالناتج ٧ أيام والسجلات ٣ أيام. لا تعتمد مهمة البناء أو تشغيل التطبيق على اشتراك ChatGPT. تختلف حصة GitHub Actions بحسب الخطة وكون المستودع عامًا أو خاصًا؛ راجع حصة حسابك قبل تشغيل نسخ إضافية. السكربت لا يفعّل دفعًا أو يرفع سقف الإنفاق.

لفحص المحاكي والجهاز دون تجهيز IPA: **Actions → Luqma iPhone build → Run workflow → check**. ينتج `Luqma-Simulator.zip` لمحاكي Mac فقط، ولا يثبت هذا الملف على الآيفون.

## التثبيت الشخصي المجاني عبر AltStore Classic

1. على ويندوز ثبّت [iTunes من Apple](https://www.apple.com/itunes/download/win64) و[iCloud من Apple](https://updates.cdn-apple.com/2020/windows/001-39935-20200911-1A70AA56-F448-11EA-8CC0-99D41950005E/iCloudSetup.exe). اتبع النسخ المباشرة المذكورة في دليل AltStore؛ يوجد مسار بديل في دليله إذا كنت تحتاج نسخة iCloud من Microsoft Store.
2. نزّل [AltServer لويندوز](https://cdn.altstore.io/file/altstore/altinstaller.zip)، فك الضغط وشغّل `Setup.exe`. بعد التثبيت شغّل **AltServer** بصفة مسؤول واسمح بالشبكة الخاصة عند الطلب.
3. وصل الآيفون بسلك، افتح قفل الشاشة واضغط **وثوق** بالكمبيوتر. افتح iTunes، سجّل الدخول، وفعّل **Sync with this iPhone over Wi-Fi** من صفحة الجهاز.
4. من أيقونة AltServer بجانب ساعة ويندوز اختر **Install AltStore** ثم الآيفون. أدخل حساب Apple في نافذة AltServer على كمبيوترك.
5. على الآيفون افتح **الإعدادات → عام → VPN وإدارة الجهاز** ثم وثوق بحساب المطور، وفعّل **الإعدادات → الخصوصية والأمان → نمط المطور** إذا طلب النظام ذلك.
6. بعد نجاح البناء احفظ `Luqma-Sideload.ipa` في تطبيق الملفات على الآيفون، ثم افتح **AltStore → My Apps → +** واختره. أبقِ AltServer يعمل والآيفون متصلًا بالكمبيوتر أو على الشبكة نفسها.
7. قبل انتهاء ٧ أيام افتح **AltStore → My Apps → Refresh All** والكمبيوتر متصل ويشغّل AltServer. إذا انتهى AltStore نفسه، أعد تثبيته من AltServer دون حذف نسخته أولًا.

أبقِ **نمط المطور** مفعّلًا طوال فترة استخدام AltStore ولُقمة المثبت بهذه الطريقة؛ إيقافه يمنع تشغيلهما. لا يلزم إبقاء الكمبيوتر أو AltServer يعملان أثناء الاستخدام اليومي؛ تحتاجهما للتثبيت والتجديد.

هذا المسار لا يحتاج شهادة توزيع مدفوعة، لكن تجديد التوقيع شرط للحساب المجاني. لا ترسل كلمة مرور Apple في المحادثة. لم يُختبر تثبيت لُقمة أو تجديده أو تفعيل HealthKit عبر حساب مجاني على جهاز فعلي بعد؛ صلاحية صحتي تعتمد أيضًا على ما يسمح به فريق التوقيع.

## التوزيع بشهادة Apple بدل AltStore

اختر طريقة التوزيع المناسبة، ثم جهّز شهادة **Apple Distribution** بمفتاحها الخاص وملف التوقيع المطابق من حساب Apple Developer الذي تملكه:

| اختيار المهمة | ملف التوقيع | الناتج واستخدامه |
|---|---|---|
| `ad-hoc` | Ad Hoc، ويحتوي الآيفون مسجلًا ضمن الأجهزة | IPA للأجهزة المسجلة في الملف فقط؛ يمكن تثبيته بأداة تدعم Ad Hoc من ويندوز. |
| `app-store` | App Store Connect | IPA لرفعه إلى App Store Connect ثم توزيعه عبر TestFlight أو App Store؛ لا يثبت مباشرة على الآيفون. |

التوزيع بهذه الطرق يحتاج عضوية Apple Developer المناسبة. لا يضيف المشروع حساب Apple أو شهادة تلقائيًا، ولا يرسل التطبيق إلى المتجر. يمكن استخدام Xcode على Mac للتثبيت الشخصي وفق صلاحيات فريقك دون اختيار أحد هذين مساري التوزيع.

في حساب Apple، أنشئ App ID فريدًا لتطبيقك وفعّل **HealthKit** عليه قبل توليد ملف التوقيع. المعرّف الافتراضي المحايد `app.luqma.diary` يجب استبداله بمعرّف تملكه عند التوزيع.

من المستودع: **Settings → Secrets and variables → Actions**:

| النوع | الاسم | القيمة |
|---|---|---|
| Variable | `BUNDLE_ID` | معرّف التطبيق المطابق تمامًا لـ App ID وملف التوقيع. |
| Variable | `APPLE_TEAM_ID` | معرّف فريق Apple، عشرة أحرف/أرقام. |
| Secret | `BUILD_CERTIFICATE_BASE64` | ملف الشهادة `.p12` ومفتاحها الخاص بصيغة Base64. |
| Secret | `P12_PASSWORD` | كلمة مرور ملف `.p12`؛ يمكن أن تكون فارغة إذا لم يكن مشفرًا بكلمة مرور. |
| Secret | `BUILD_PROVISION_PROFILE_BASE64` | ملف `.mobileprovision` بصيغة Base64. |

لا تضع ملفات التوقيع في مجلد المصدر. لتحويل ملف لديك من PowerShell وإرساله مباشرة إلى Secret دون طباعة محتواه:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\Signing\Luqma.p12')) | gh secret set BUILD_CERTIFICATE_BASE64
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\Signing\Luqma.mobileprovision')) | gh secret set BUILD_PROVISION_PROFILE_BASE64
gh secret set P12_PASSWORD
```

شغّل هذه الأوامر من مجلد المشروع المرتبط بالمستودع. الأمر الأخير يطلب كلمة المرور دون حفظها في مصدر التطبيق؛ لا ترسل كلمة مرور حساب Apple داخل المحادثة.

بعد إضافة القيم: **Actions → Luqma iPhone build → Run workflow** واختر `ad-hoc` أو `app-store`. السكربت يتحقق من الفريق ومعرّف التطبيق وصلاحية HealthKit وتاريخ الملف والشهادة الخاصة المطابقة. يُحذف مفتاح التوقيع المؤقت وتُستعاد ملفات التوقيع السابقة بعد التنفيذ. عند النجاح حمّل `Luqma.ipa` و`build-summary.json`.

رقم البناء يتغير تلقائيًا حسب رقم تشغيل المهمة. يستخدم البناء Xcode 26.3 على `macos-15`، والإصدار الأدنى للتطبيق iOS 17. مسار App Store يتطلب Xcode 26 أو أحدث وفق متطلبات Apple الحالية. يمكن تعيين Variable باسم `XCODE_DEVELOPER_DIR` لمسار إصدار Xcode آخر مثبت على جهاز البناء إذا تغيرت صورة الخدمة.

## حدود ما تم إنجازه

نجح البناء رقم ٢٤ في ٢٦ اختبار Swift و١٦ اختبار أدوات البناء وتجميع iPhoneOS Release وإنتاج IPA وفحص النموذجين 2B و4B على Mac. اجتاز كلاهما فئات الوجبة العامة المطلوبة ورفض صورة الاختبار الخالية من الطعام مع تعطيل التنزيل. استغرق الفحص نحو ٢٧٩٫٠٩ ثانية للنموذج الأصغر و٣٩٧٫٢٩ ثانية للأكبر، بما فيها التنزيل والتحميل على جهاز البناء؛ هذه ليست سرعة الآيفون ولا قياسًا لدقة السعرات.

تضيف الشيفرة مسارًا نصيًا مستقلًا لاستكمال القيم الغذائية الناقصة للأطعمة غير المطابقة للمرجع، وفق مواضعها الأصلية ومن دون تغيير أسمائها أو كمياتها أو عددها أو تغذية الأطعمة المرجعية. تبقى هذه القيم تقديرات قابلة للمراجعة. كما توضح التعليمات الفرق العام بين الخبز غير المحشو واللفافة المحشوة. اختبارات دمج هذا المسار ورفض القيم غير الصالحة نجحت؛ نتائج الصور في البناء ٢٤ تضمنت القيم الغذائية أصلًا، لذلك لا يُعد هذا البناء إثباتًا لتشغيل الفرع النصي نفسه مع النموذج. سبق أن فشل البناءان ٢٢ و٢٣ في فحص الصور؛ لا تستخدم ملفيهما بدل البناء ٢٤.

التوقيع المحلي ليس توقيع حساب Apple؛ تتولى أداة التثبيت إعادة توقيعه لحسابك وجهازك. مسارا Ad Hoc وApp Store بتوقيع Apple لم يُنفَّذا. لم تُجرَّب النسخة النهائية على آيفون فعلي بعد؛ الكاميرا وصحتي وتحليل الصور والتجديد الأسبوعي والتحقق من زوال الإغلاق تحتاج التجربة على الجهاز. التفاصيل والبصمة في `VALIDATION.md`.

المراجع الرسمية:

- [أجهزة البناء لدى GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [توقيع تطبيقات Xcode على GitHub](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [إنشاء ملف Ad Hoc لدى Apple](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/)
- [إصدارات Xcode على صورة macOS 15](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md)
- [متطلبات رفع التطبيقات لدى Apple](https://developer.apple.com/news/upcoming-requirements/)
- [تثبيت AltStore Classic على ويندوز](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
- [تجديد التطبيقات في AltStore](https://faq.altstore.io/altstore-classic/your-altstore)
- [الاتصال بالكمبيوتر وتجديد AltStore المنتهي](https://faq.altstore.io/altstore-classic/altserver)
- [حصة GitHub Actions والفوترة](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
