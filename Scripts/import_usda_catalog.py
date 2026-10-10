"""Rebuild the offline catalog from the pinned public-domain USDA SR Legacy ZIP.

Usage: python3 Scripts/import_usda_catalog.py /path/to/sr_legacy.zip
Obtain that ZIP from SOURCE_URL. The source archive is not bundled in the app.
Nutrition is copied per 100 g, including explicit zeroes. Arabic aliases are
search keywords, not translations of complete dishes or substitute nutrients.
"""
import argparse
import hashlib
import json
import math
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCE_DIR = ROOT / "Luqma" / "Resources"
SOURCE_URL = "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip"
SOURCE_SHA256 = "0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef"
SOURCE_COUNT = 7793
NUTRIENTS = {"kcal": 1008, "protein": 1003, "carbs": 1005, "fat": 1004}
NUTRIENT_UNITS = {1008: "kcal", 1003: "g", 1005: "g", 1004: "g"}
LABEL_FIELDS = {"id", "name", "nameEn", "aliases", "brand", "barcode", "serving", "servingEn", "servingQuantity", "servingUnit"}

# Deliberately small and inspectable. Whole words prevent false matches such as
# pita/Pitanga. Keywords help Arabic users find the original English USDA name.
ARABIC_SEARCH_TERMS = (
    (r"eggs?", "بيض بيضة بيضه بيضات"),
    (r"egg whites?|white of egg", "بياض بيض"),
    (r"egg yolks?|yolk", "صفار بيض"),
    (r"chickens?", "دجاج فراخ"),
    (r"turkeys?", "ديك رومي"),
    (r"beef|veal", "لحم بقري بقر عجل"),
    (r"lamb|mutton", "لحم غنم ضأن خروف"),
    (r"goat", "لحم ماعز"),
    (r"pork|ham|bacon", "لحم خنزير"),
    (r"fish|salmon|tuna|tilapia|sardines?|cod|trout|haddock|mackerel", "سمك أسماك"),
    (r"salmon", "سلمون"),
    (r"tuna", "تونة تونا"),
    (r"shrimp|prawns?", "روبيان جمبري"),
    (r"crab|lobster", "سلطعون استاكوزا"),
    (r"milk", "حليب لبن"),
    (r"yogurt|yoghurt", "زبادي روب"),
    (r"cheese|cheddar|mozzarella|feta|parmesan|ricotta", "جبن جبنة"),
    (r"butter", "زبدة"),
    (r"cream", "كريمة"),
    (r"ice cream", "آيس كريم ايسكريم"),
    (r"rice", "أرز ارز رز"),
    (r"breads?|pita", "خبز"),
    (r"pita", "خبز عربي بيتا"),
    (r"pasta|macaroni|spaghetti|noodles?", "مكرونة معكرونة باستا"),
    (r"oats?|oatmeal", "شوفان"),
    (r"wheat", "قمح"),
    (r"flour", "دقيق طحين"),
    (r"corn|maize", "ذرة"),
    (r"barley", "شعير"),
    (r"quinoa", "كينوا"),
    (r"cereal|cereals", "حبوب إفطار فطور"),
    (r"beans?", "فاصوليا"),
    (r"lentils?", "عدس"),
    (r"chickpeas?|garbanzo", "حمص حب"),
    (r"hummus", "حمص مهروس"),
    (r"falafel", "فلافل طعمية"),
    (r"tahini", "طحينة"),
    (r"peas?", "بازلاء بسلة"),
    (r"soy|soybeans?|tofu", "صويا"),
    (r"potatoes?|potato", "بطاطس بطاطا"),
    (r"tomatoes?|tomato", "طماطم بندورة"),
    (r"cucumbers?", "خيار"),
    (r"carrots?", "جزر"),
    (r"onions?", "بصل"),
    (r"garlic", "ثوم"),
    (r"broccoli", "بروكلي"),
    (r"cauliflower", "قرنبيط زهرة"),
    (r"spinach", "سبانخ"),
    (r"lettuce", "خس"),
    (r"cabbage", "ملفوف كرنب"),
    (r"eggplant|aubergine", "باذنجان"),
    (r"zucchini|courgette", "كوسا"),
    (r"mushrooms?", "فطر مشروم"),
    (r"pepper|peppers", "فلفل"),
    (r"avocados?", "أفوكادو افوكادو"),
    (r"olives?", "زيتون"),
    (r"apples?", "تفاح"),
    (r"bananas?", "موز"),
    (r"oranges?", "برتقال"),
    (r"lemons?", "ليمون"),
    (r"grapes?", "عنب"),
    (r"strawberries|strawberry", "فراولة"),
    (r"blueberries|blueberry", "توت أزرق"),
    (r"dates?", "تمر تمور"),
    (r"figs?", "تين"),
    (r"mangoes?|mangos?", "مانجو"),
    (r"pineapples?", "أناناس اناناس"),
    (r"watermelon", "بطيخ"),
    (r"melons?", "شمام"),
    (r"peaches?", "خوخ"),
    (r"pears?", "كمثرى"),
    (r"apricots?", "مشمش"),
    (r"raisins?", "زبيب"),
    (r"almonds?", "لوز"),
    (r"walnuts?", "جوز"),
    (r"cashews?", "كاجو"),
    (r"pistachios?", "فستق"),
    (r"peanuts?", "فول سوداني"),
    (r"sesame", "سمسم"),
    (r"sunflower", "عباد شمس دوار الشمس"),
    (r"coconut", "جوز هند"),
    (r"oils?|shortening", "زيت"),
    (r"honey", "عسل"),
    (r"sugars?", "سكر"),
    (r"chocolate|cocoa", "شوكولاتة شوكولاته كاكاو"),
    (r"coffee", "قهوة"),
    (r"tea", "شاي"),
    (r"juice", "عصير"),
    (r"water", "ماء مياه"),
    (r"soft drinks?|soda|cola", "مشروب غازي صودا"),
    (r"salads?", "سلطة سلطه"),
    (r"soups?", "شوربة حساء"),
    (r"sauces?|gravy|mayonnaise|ketchup|dressings?", "صلصة صوص"),
    (r"pizza", "بيتزا"),
    (r"burgers?|hamburgers?", "برجر همبرجر"),
    (r"sandwiches?|sandwich", "ساندويتش سندويش"),
    (r"sausages?|frankfurters?|hot dogs?", "نقانق سجق"),
    (r"biscuits?|cookies?", "بسكويت كوكيز"),
    (r"cakes?", "كيك كعك"),
    (r"crackers?", "بسكويت مالح"),
    (r"chips?", "رقائق شيبس"),
    (r"salts?", "ملح"),
    (r"breasts?", "صدر صدور"),
    (r"thighs?", "فخذ أفخاذ"),
    (r"wings?", "جناح أجنحة"),
    (r"raw", "نيء نيئ نيئة"),
    (r"cooked", "مطبوخ مطبوخة"),
    (r"grilled", "مشوي مشوية"),
    (r"roasted|baked", "فرن"),
    (r"fried", "مقلي مقلية"),
    (r"boiled", "مسلوق مسلوقة"),
    (r"frozen", "مجمد مجمدة"),
    (r"dried|dehydrated", "مجفف مجففة"),
    (r"canned", "معلب معلبة"),
    (r"skinless", "بدون جلد"),
    (r"whole wheat|whole grain", "قمح كامل حبوب كاملة"),
    (r"low fat|lowfat|reduced fat", "قليل الدسم"),
    (r"nonfat|fat free|skim", "خالي الدسم"),
    (r"unsweetened|without sugar", "غير محلى بدون سكر"),
)
SEARCH_RULES = tuple((re.compile(r"\b(?:" + pattern + r")\b", re.IGNORECASE), arabic)
                     for pattern, arabic in ARABIC_SEARCH_TERMS)


def arabic_aliases(description):
    terms = []
    for pattern, arabic in SEARCH_RULES:
        if pattern.search(description.replace("-", " ")):
            terms.extend(arabic.split())
    return " ".join(dict.fromkeys(terms))


def load_source(archive_path):
    path = Path(archive_path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != SOURCE_SHA256:
        raise ValueError("Source ZIP SHA-256 does not match the pinned official SR Legacy release.")
    with zipfile.ZipFile(path) as archive:
        damaged = archive.testzip()
        if damaged:
            raise ValueError("Damaged source ZIP member: " + damaged)
        members = [name for name in archive.namelist() if name.endswith(".json")]
        if len(members) != 1:
            raise ValueError("Expected exactly one USDA JSON member.")
        rows = json.loads(archive.read(members[0]))["SRLegacyFoods"]
    if len(rows) != SOURCE_COUNT:
        raise ValueError("Unexpected SR Legacy record count.")
    return rows


def convert_records(rows, labels):
    metadata = {}
    for item in labels:
        if set(item) - LABEL_FIELDS:
            raise ValueError("Label metadata contains unsupported or nutritional fields.")
        identifier = item["id"]
        if identifier in metadata:
            raise ValueError("Duplicate label ID: " + identifier)
        metadata[identifier] = item
    foods = {}
    for row in rows:
        source_id = str(row["fdcId"])
        identifier = "usda:" + source_id
        if identifier in foods:
            raise ValueError("Duplicate USDA food ID: " + source_id)
        nutrients = {}
        for item in row["foodNutrients"]:
            nutrient_id = item["nutrient"]["id"]
            if nutrient_id not in NUTRIENT_UNITS:
                continue
            amount = item.get("amount")
            if type(amount) not in (int, float) or not math.isfinite(amount) or amount < 0 or amount > 100000:
                raise ValueError("Invalid nutrient value for " + identifier)
            if item["nutrient"]["unitName"].lower() != NUTRIENT_UNITS[nutrient_id]:
                raise ValueError("Unexpected nutrient unit for " + identifier)
            if nutrient_id in nutrients:
                raise ValueError("Duplicate nutrient for " + identifier)
            nutrients[nutrient_id] = amount
        if set(nutrients) != set(NUTRIENT_UNITS):
            raise ValueError("Incomplete nutrient profile for " + identifier)
        description = row["description"]
        if not isinstance(description, str) or not description.strip():
            raise ValueError("Missing food description for " + identifier)
        food = {"id": identifier, "name": description, "nameEn": description,
                "unit": "g", "baseUnit": "g", "source": "USDA", "sourceId": source_id,
                "sourceDescription": description}
        if identifier in metadata:
            food.update(metadata[identifier])
        else:
            aliases = arabic_aliases(description)
            if aliases:
                food["aliases"] = aliases
        food.update({name: nutrients[nutrient_id] for name, nutrient_id in NUTRIENTS.items()})
        quantity = food.get("servingQuantity")
        if quantity is not None:
            if type(quantity) not in (int, float) or not math.isfinite(quantity) or quantity <= 0 or food.get("servingUnit") != "g":
                raise ValueError("Invalid preserved serving for " + identifier)
            food["servingNutrition"] = {name: food[name] * quantity / 100 for name in NUTRIENTS}
        foods[identifier] = food
    missing_labels = set(metadata) - set(foods)
    if missing_labels:
        raise ValueError("Label IDs absent from source: " + ", ".join(sorted(missing_labels)))
    # Retain the previous Arabic catalog order, then add the full source set.
    ordered = [foods.pop(item["id"]) for item in labels]
    ordered.extend(foods[key] for key in sorted(foods, key=lambda key: int(key.split(":")[1])))
    return ordered


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_zip", type=Path)
    parser.add_argument("--labels", type=Path, default=RESOURCE_DIR / "food-catalog-labels.json")
    parser.add_argument("--output", type=Path, default=RESOURCE_DIR / "foods-data.json")
    arguments = parser.parse_args()
    foods = convert_records(load_source(arguments.source_zip), json.loads(arguments.labels.read_text(encoding="utf-8")))
    data = json.dumps(foods, ensure_ascii=False, separators=(",", ":")) + "\n"
    arguments.output.write_text(data, encoding="utf-8", newline="\n")
    print(json.dumps({"count": len(foods), "bytes": len(data.encode("utf-8")),
                      "source_sha256": SOURCE_SHA256,
                      "output_sha256": hashlib.sha256(data.encode("utf-8")).hexdigest()}))


if __name__ == "__main__":
    main()
