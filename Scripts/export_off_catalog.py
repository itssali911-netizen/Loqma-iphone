"""Export the exact native OFF starter cache to JSON and portable SQLite.

The native iPhone app reads JSON. SQLite is an optional portable export, not
the application's storage engine. No network calls or OFF images are used.
"""
import argparse
import hashlib
import json
import re
import shutil
import sqlite3
import unicodedata
import zipfile
from pathlib import Path
from import_off_catalog import ROOT, generate, load_snapshot


def normalized(text):
    value = "".join(unicodedata.normalize("NFKC", char)
                    if unicodedata.decomposition(char).startswith(("<wide>", "<narrow>"))
                    else char for char in str(text).lower())
    for old, new in [("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ٱ", "ا"), ("ى", "ي"),
                     ("ة", "ه"), ("ـ", ""), ("ؤ", "و"), ("ئ", "ي"), ("ی", "ي"), ("ک", "ك")]:
        value = value.replace(old, new)
    for digits in ["٠١٢٣٤٥٦٧٨٩", "۰۱۲۳۴۵۶۷۸۹"]:
        for number, char in enumerate(digits):
            value = value.replace(char, str(number))
    result, separating = [], False
    for char in unicodedata.normalize("NFD", value):
        if unicodedata.category(char).startswith("M"):
            continue
        if char.isalnum():
            if separating and result:
                result.append(" ")
            result.append(char)
            separating = False
        else:
            separating = True
    return "".join(result)


def search_text(food):
    names = [normalized(food["name"])]
    if food.get("nameEn") is not None:
        names.append(normalized(food["nameEn"]))
    aliases = [normalized(value) for value in re.split(r"[,،;؛|\n]", food.get("aliases") or "")]
    return " ".join(names + [value for value in aliases if value] + [normalized(food.get("brand") or "")])


def search_sql(query):
    tokens = list(dict.fromkeys(normalized(query).split()))
    clauses = " AND ".join("instr(search_text, ?) > 0" for _ in tokens) if tokens else "0"
    return "SELECT id FROM foods WHERE " + clauses + " ORDER BY id", tokens


def export(output):
    data, provenance = generate(load_snapshot())
    native_data = (ROOT / "Luqma/Resources/foods-data.json").read_bytes().replace(b"\r\n", b"\n")
    if data != native_data:
        raise ValueError("The source response snapshot does not reproduce the native catalog")
    foods = json.loads(data)
    output.mkdir(parents=True, exist_ok=True)
    (output / "foods-data.json").write_bytes(data)
    (output / "food-catalog-provenance.json").write_bytes(provenance)
    for name in ["NOTICE.txt", "LICENSES.txt"]:
        (output / name).write_bytes((ROOT / "Luqma/Resources" / name).read_bytes().replace(b"\r\n", b"\n"))
    shutil.copyfile(ROOT / "Scripts/Data/off-products-snapshot.json", output / "off-products-snapshot.json")
    db_path = output / "foods.sqlite"
    if db_path.exists():
        db_path.unlink()
    db = sqlite3.connect(db_path)
    db.execute("PRAGMA foreign_keys=ON")
    db.execute("""CREATE TABLE foods (
        id TEXT PRIMARY KEY, native_id TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
        name_en TEXT, aliases TEXT, brand TEXT, barcode TEXT, unit TEXT NOT NULL,
        kcal REAL, protein REAL, carbs REAL, fat REAL,
        source TEXT NOT NULL CHECK(source='OpenFoodFacts'), source_id TEXT NOT NULL,
        source_description TEXT, search_text TEXT NOT NULL, food_json TEXT NOT NULL)""")
    db.execute("""CREATE TABLE servings (
        id TEXT PRIMARY KEY, food_id TEXT NOT NULL REFERENCES foods(id),
        label TEXT NOT NULL, quantity REAL, unit TEXT,
        kcal REAL NOT NULL, protein REAL NOT NULL, carbs REAL NOT NULL, fat REAL NOT NULL,
        CHECK(quantity IS NULL OR quantity>0), CHECK(unit IS NULL OR unit IN ('g','ml')))""")
    for food in foods:
        native_id = "barcode:" + food["barcode"] if food.get("barcode") else food["id"]
        db.execute("INSERT INTO foods VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
            food["id"], native_id, food["name"], food.get("nameEn"), food.get("aliases"), food.get("brand"),
            food.get("barcode"), food["unit"], food.get("kcal"), food.get("protein"), food.get("carbs"), food.get("fat"),
            food["source"], food["sourceId"], food.get("sourceDescription"), search_text(food),
            json.dumps(food, ensure_ascii=False, separators=(",", ":"), allow_nan=False)))
        if serving := food.get("servingNutrition"):
            db.execute("INSERT INTO servings VALUES (?,?,?,?,?,?,?,?,?)", (
                "off-serving:" + food["sourceId"], food["id"], food.get("serving") or "1 serving",
                food.get("servingQuantity"), food.get("servingUnit"),
                serving["kcal"], serving["protein"], serving["carbs"], serving["fat"]))
    db.commit()
    integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
    foreign_keys = db.execute("PRAGMA foreign_key_check").fetchall()
    if integrity != "ok" or foreign_keys:
        raise ValueError("SQLite integrity failed")
    for identifier, raw in db.execute("SELECT id,food_json FROM foods"):
        if json.loads(raw) != next(food for food in foods if food["id"] == identifier):
            raise ValueError("SQLite food differs from native JSON")
    queries = []
    for query in ["milk", "حليب", "Almarai", "nutella", "pesto"]:
        actual = [row[0] for row in db.execute(*search_sql(query))]
        tokens = list(dict.fromkeys(normalized(query).split()))
        expected = sorted(food["id"] for food in foods if tokens and all(word in search_text(food) for word in tokens))
        if actual != expected:
            raise ValueError("SQLite search differs from local contains matching")
        queries.append({"query": query, "count": len(actual), "ids": actual})
    serving_count = db.execute("SELECT COUNT(*) FROM servings").fetchone()[0]
    db.close()
    (output / "README-AR.md").write_text("""# قاعدة Open Food Facts للُقمة

هذا تصدير **العينة المحلية فقط: ٦ منتجات حقيقية و٥ حصص معلنة**، وليس قاعدة Open Food Facts كاملة.
التطبيق يجلب بقية المنتجات بالبحث أو الباركود مباشرة من Open Food Facts، ويحفظ المنتجات المستخدمة دون اتصال.
ملف foods-data.json مطابق لمورد التطبيق، وfoods.sqlite تصدير مستقل قابل لإعادة الاستخدام.
لا يستخدم التطبيق SQLite داخليًا. لا يحتوي التصدير على بيانات يوميات أو حسابات أو صور.

قاعدة البيانات مشتقة من Open Food Facts تحت ODbL 1.0 ومحتوياتها تحت Database Contents License 1.0.
المصدر: https://world.openfoodfacts.org/ . الشروط: https://world.openfoodfacts.org/terms-of-use .
يرفق التصدير تفاصيل المصدر والاستجابات الخام وبصمات الملفات والترخيص.
قد تكون بيانات المصدر ناقصة أو خاطئة؛ راجع الملصق. لا نستنتج كثافة لتحويل الجرام إلى الملليلتر.

جدول foods يحفظ هوية المصدر off:، وهوية التطبيق native_id، الاسم والوحدات والقيم لكل ١٠٠ وfood_json كاملًا.
جدول servings يحفظ الحصة بالكمية والوحدة والقيم الغذائية المعلنة، بما فيها حصص السوائل.
يعرض بحث SQLite جميع الصفوف التي يحتوي search_text فيها كل كلمات الاستعلام بعد التطبيع؛ القيم تُمرّر بمعاملات مربوطة.
التطبيع البرمجي وعبارة البحث محفوظان في Scripts/export_off_catalog.py داخل مصدر التطبيق.
هذا لا يكرر ترتيب Best match تلقائيًا؛ التطبيق يضيف ترتيب الاسم المطابق ثم البداية ثم بقية المطابقات.
مثال SQL لكلمة واحدة: SELECT id,name FROM foods WHERE instr(search_text, ?) > 0;
إعادة البناء: python3 Scripts/import_off_catalog.py ثم python3 Scripts/export_off_catalog.py --output مسار_التصدير.
""", encoding="utf-8", newline="\n")
    report = {"food_count": len(foods), "serving_count": serving_count, "catalog_sha256": hashlib.sha256(data).hexdigest(),
              "sqlite_version": sqlite3.sqlite_version, "unicode_version": unicodedata.unidata_version,
              "integrity_check": integrity, "foreign_key_check": foreign_keys, "queries": queries,
              "native_uses_sqlite": False, "external_source": "Open Food Facts"}
    (output / "export-validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    members = sorted(path for path in output.iterdir() if path.is_file() and path.name not in {"SHA256SUMS.txt", "off-food-database.zip"})
    (output / "SHA256SUMS.txt").write_text("".join(hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name + "\n" for path in members), encoding="utf-8", newline="\n")
    archive = output / "off-food-database.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zipped:
        for path in members + [output / "SHA256SUMS.txt"]:
            zipped.write(path, path.name)
    with zipfile.ZipFile(archive) as zipped:
        if zipped.testzip() is not None:
            raise ValueError("Export archive CRC failed")
    print(json.dumps({**report, "zip_bytes": archive.stat().st_size, "zip_sha256": hashlib.sha256(archive.read_bytes()).hexdigest()}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    export(parser.parse_args().output)
