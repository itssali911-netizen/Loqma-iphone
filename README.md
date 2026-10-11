# Luqma Native iOS

Version 1.5 implements an Open Food Facts food catalog and live product search, a promoted **Best match**, **Serving** as the default addition unit, and simpler food, progress and Health screens. Build through `Scripts/build_ios.py` on Xcode 26.3+; iPhone / iOS 17+. See [Arabic instructions](README-AR.md), [food sources](FOOD-DATA-AR.md) and [validation history](VALIDATION.md).

The bundled starter cache contains six inspected Open Food Facts products; it is not a full database download. Submitted searches and barcode lookups query Open Food Facts, and saved products remain usable offline. All query words must occur in names, aliases or brand in any order. Exact names and prefixes rank ahead of other contains matches; the first loaded result is promoted as Best match without duplicating it. Search has explicit pagination and an external 10,000-hit window. No private MyFitnessPal data or ranking algorithm is included.

The active USDA catalog and importer were removed. Historical diary totals, backups and private manual foods remain intact; old third-party/AI records are excluded from new search results. Photo recognition proposes food names and approximate weights only: each component requires choosing an Open Food Facts product and quantity before logging. The active photo-category resource contains no nutrition values. Historical regression fixtures are test-only.

Every quantity form starts at one Serving. A declared source serving is used when available. Otherwise the user supplies the serving's weight/volume from the label or selects the product's original g/ml unit; no size or density is invented. Nutrition details are collapsed for complete products. Recent/Frequent are based on actual diary entries, and My foods contains private manually created foods.

Apple Health has a compact dedicated connection screen and signing help. The screenshot's installed identifier is `app.luqma.diary.2AV9NV468K`: back up first, preserve that exact identifier and the same Apple account when re-signing an update. Both HealthKit and background delivery must be allowed by the final Apple signature/profile; after installation, connect and consent on the iPhone. See [HEALTH-SETUP-AR.md](HEALTH-SETUP-AR.md). Manual Health XML import remains a snapshot, separate from automatic synchronization.

The built sideload IPA requires personal Apple re-signing. No Apple account, certificate, API key or ChatGPT subscription is embedded. Native compilation and fixture tests run in GitHub Actions on macOS/Xcode; physical-iPhone Health authorization, background behavior, camera and memory handling require device verification. Current verification status is recorded in VALIDATION.md.

Core tests are a standalone Swift package. Run `bash Scripts/verify.sh` on macOS. Rebuild the deterministic OFF starter catalog with `python3 Scripts/import_off_catalog.py`; pinned response checksums, source units and ODbL/Database Contents License attribution are bundled.
