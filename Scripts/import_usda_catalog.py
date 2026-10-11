"""Rebuild the offline catalog from two pinned public-domain USDA ZIPs.

Usage: python3 Scripts/import_usda_catalog.py /path/to/sr_legacy.zip /path/to/survey.zip
Obtain the ZIPs from SOURCE_URL and SURVEY_SOURCE_URL. Neither is bundled.
Nutrition is copied per 100 g, including explicit zeroes. Arabic aliases are
search keywords, not translations of complete dishes or substitute nutrients.
Named portions retain their published gram weights; no liquid density or
milliliter conversion is inferred. One incomplete FNDDS record is excluded.
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
SURVEY_SOURCE_URL = "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_json_2024-10-31.zip"
SURVEY_SOURCE_SHA256 = "dfb06ae7ddc397ccd570b91c14b75438ab2ba39f64f22d321f61d4a52a77f3eb"
SURVEY_SOURCE_COUNT = 5432
SURVEY_EXCLUDED_IDS = {2705383: "Milk, human: source has no energy, protein, carbohydrate or fat values."}
CATALOG_COUNT = SOURCE_COUNT + SURVEY_SOURCE_COUNT - len(SURVEY_EXCLUDED_IDS)
DATASETS = {
    "sr_legacy": {"name": "SR Legacy, final April 2018 release", "source_url": SOURCE_URL,
                  "source_sha256": SOURCE_SHA256, "source_zip_bytes": 13456312,
                  "array_key": "SRLegacyFoods", "source_food_count": SOURCE_COUNT,
                  "source_portion_count": 14449},
    "survey": {"name": "FNDDS 2021-2023, October 31, 2024 release", "source_url": SURVEY_SOURCE_URL,
               "source_sha256": SURVEY_SOURCE_SHA256, "source_zip_bytes": 3835292,
               "array_key": "SurveyFoods", "source_food_count": SURVEY_SOURCE_COUNT,
               "source_portion_count": 22194},
}
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


def load_source(archive_path, dataset="sr_legacy"):
    if dataset not in DATASETS:
        raise ValueError("Unknown USDA dataset.")
    expected = DATASETS[dataset]
    path = Path(archive_path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != expected["source_sha256"]:
        raise ValueError("Source ZIP SHA-256 does not match the pinned official " + expected["name"] + ".")
    with zipfile.ZipFile(path) as archive:
        damaged = archive.testzip()
        if damaged:
            raise ValueError("Damaged source ZIP member: " + damaged)
        members = [name for name in archive.namelist() if name.endswith(".json")]
        if len(members) != 1:
            raise ValueError("Expected exactly one USDA JSON member.")
        rows = json.loads(archive.read(members[0]))[expected["array_key"]]
    if len(rows) != expected["source_food_count"]:
        raise ValueError("Unexpected " + expected["name"] + " record count.")
    if sum(len(row.get("foodPortions", [])) for row in rows) != expected["source_portion_count"]:
        raise ValueError("Unexpected " + expected["name"] + " portion count.")
    return rows


def positive_number(value):
    return type(value) in (int, float) and math.isfinite(value) and 0 < value <= 10000


def portion_label(portion):
    """FNDDS descriptions are full labels; SR modifiers need their amount."""
    full = portion.get("portionDescription")
    if isinstance(full, str) and full.strip():
        label = " ".join(full.split())
    else:
        amount = portion.get("amount")
        if not positive_number(amount):
            return None
        modifier = portion.get("modifier", "")
        if not isinstance(modifier, str):
            return None
        modifier = " ".join(modifier.split())
        measure = portion.get("measureUnit", {}).get("name", "")
        if not isinstance(measure, str):
            return None
        measure = " ".join(measure.split())
        if measure.lower() == "undetermined":
            measure = ""
        # Numeric modifiers are source codes, never names such as a cup/slice.
        if modifier.isdigit():
            return None
        if not measure and not modifier:
            return None
        # A real measure and its modifier describe one full source portion.
        if measure and modifier:
            descriptor = modifier if modifier.lower().startswith(measure.lower()) else measure + " " + modifier
        else:
            descriptor = measure or modifier
        label = format(amount, ".15g") + " " + descriptor
    lowered = label.casefold()
    if len(label) > 180 or label.isdigit() or "not specified" in lowered or "undetermined" in lowered:
        return None
    return label


def convert_portions(portions):
    """Return unique, deterministic choices, preserving full-portion grams."""
    candidates = []
    for portion in portions:
        if not isinstance(portion, dict) or not positive_number(portion.get("gramWeight")):
            continue
        source_id = portion.get("id")
        if type(source_id) is not int or source_id <= 0:
            continue
        label = portion_label(portion)
        if label is None:
            continue
        sequence = portion.get("sequenceNumber")
        sequence = sequence if type(sequence) is int and sequence > 0 else 100000
        candidates.append((sequence, source_id, label, portion["gramWeight"]))
    seen_ids, seen_choices, result = set(), set(), []
    for _, source_id, label, grams in sorted(candidates):
        identifier = "usda-portion:" + str(source_id)
        key = (label.casefold(), grams)
        if identifier in seen_ids or key in seen_choices:
            continue
        seen_ids.add(identifier)
        seen_choices.add(key)
        result.append({"id": identifier, "label": label, "grams": grams})
    return result


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
        # Native diary/backup names are bounded to 180 characters. Preserve a
        # longer original in provenance and in searchable aliases, marking only
        # its display label as truncated rather than excluding a valid food.
        display = description if len(description) <= 180 else description[:177].rstrip() + "..."
        food = {"id": identifier, "name": display, "nameEn": display,
                "unit": "g", "baseUnit": "g", "source": "USDA", "sourceId": source_id,
                "sourceDescription": description}
        if identifier in metadata:
            food.update(metadata[identifier])
        else:
            aliases = arabic_aliases(description)
            if aliases:
                food["aliases"] = aliases
        if display != description:
            food["aliases"] = " | ".join(part for part in [food.get("aliases"), description] if part)
        food.update({name: nutrients[nutrient_id] for name, nutrient_id in NUTRIENTS.items()})
        quantity = food.get("servingQuantity")
        if quantity is not None:
            if type(quantity) not in (int, float) or not math.isfinite(quantity) or quantity <= 0 or food.get("servingUnit") != "g":
                raise ValueError("Invalid preserved serving for " + identifier)
            food["servingNutrition"] = {name: food[name] * quantity / 100 for name in NUTRIENTS}
        servings = convert_portions(row.get("foodPortions", []))
        if servings:
            food["servings"] = servings
        foods[identifier] = food
    missing_labels = set(metadata) - set(foods)
    if missing_labels:
        raise ValueError("Label IDs absent from source: " + ", ".join(sorted(missing_labels)))
    # Retain the previous Arabic catalog order, then add the full source set.
    ordered = [foods.pop(item["id"]) for item in labels]
    ordered.extend(foods[key] for key in sorted(foods, key=lambda key: int(key.split(":")[1])))
    return ordered


def build_catalog(sr_rows, survey_rows, labels):
    # This pinned record lacks all four required nutrients. Refuse an unexpected
    # exclusion or incomplete new record rather than filling missing values with 0.
    excluded = [row for row in survey_rows if row["fdcId"] in SURVEY_EXCLUDED_IDS]
    if {row["fdcId"] for row in excluded} != set(SURVEY_EXCLUDED_IDS):
        raise ValueError("Expected incomplete FNDDS record is absent.")
    for row in excluded:
        if any(item.get("nutrient", {}).get("id") in NUTRIENT_UNITS for item in row.get("foodNutrients", [])):
            raise ValueError("Excluded FNDDS record unexpectedly has nutrition.")
    sr = convert_records(sr_rows, labels)
    survey = convert_records([row for row in survey_rows if row["fdcId"] not in SURVEY_EXCLUDED_IDS], [])
    foods = sr + survey
    if len(foods) != CATALOG_COUNT or len({food["id"] for food in foods}) != len(foods):
        raise ValueError("Unexpected combined catalog count or duplicated USDA identity.")
    return foods


def provenance(foods, catalog_bytes):
    sources = []
    for key, spec in DATASETS.items():
        source = {name: value for name, value in spec.items() if name != "array_key"}
        excluded = ([{"sourceId": str(identifier), "reason": reason}
                     for identifier, reason in sorted(SURVEY_EXCLUDED_IDS.items())] if key == "survey" else [])
        source["included_food_count"] = spec["source_food_count"] - len(excluded)
        source["excluded_records"] = excluded
        subset = foods[:SOURCE_COUNT] if key == "sr_legacy" else foods[SOURCE_COUNT:]
        source["included_serving_count"] = sum(len(food.get("servings", [])) for food in subset)
        source["excluded_portion_count"] = spec["source_portion_count"] - source["included_serving_count"]
        sources.append(source)
    return {
        "source": "U.S. Department of Agriculture, Agricultural Research Service. FoodData Central: SR Legacy and FNDDS 2021-2023.",
        "source_documentation": "https://fdc.nal.usda.gov/download-datasets/",
        "license": "CC0-1.0", "license_statement": "https://fdc.nal.usda.gov/api-guide/",
        "sources": sources, "food_count": len(foods), "catalog_bytes": len(catalog_bytes),
        "catalog_sha256": hashlib.sha256(catalog_bytes).hexdigest(),
        "foods_with_servings": sum(bool(food.get("servings")) for food in foods),
        "serving_count": sum(len(food.get("servings", [])) for food in foods),
        "nutrient_basis": "Per 100 g, copied directly from source nutrient IDs 1008 (kcal), 1003 (protein), 1005 (carbohydrate), and 1004 (fat). Source calorie values and precision are preserved; they are not recalculated from macros. Missing nutrients are never replaced by zero.",
        "servings": "Optional choices copy explicit USDA gram weights for the full portion label. SR labels combine source amount with its measure/modifier; FNDDS labels use portionDescription rather than numeric modifier codes. Non-positive or invalid weights/amounts, unnamed or 'Quantity not specified' portions and duplicates are excluded. No ml conversion or liquid density is inferred. Four existing legacy serving fields are preserved.",
        "labels": "The 94 existing Arabic names, IDs, aliases and single-serving descriptions are preserved in food-catalog-labels.json. Added foods keep exact English source descriptions. One description exceeds the native 180-character display-name limit: its displayed name uses an ellipsis, while sourceDescription and a search alias retain the full original. Arabic aliases are curated search keywords in Scripts/import_usda_catalog.py, not complete translations or new recipe identities. Portion labels retain source English.",
        "rebuild": "python3 Scripts/import_usda_catalog.py /path/to/FoodData_Central_sr_legacy_food_json_2018-04.zip /path/to/FoodData_Central_survey_food_json_2024-10-31.zip",
        "scope": "This is an open USDA catalog, separate from online Open Food Facts branded product results. It is not the MyFitnessPal database. Photo recognition reference foods are maintained separately.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_zip", type=Path)
    parser.add_argument("survey_zip", type=Path)
    parser.add_argument("--labels", type=Path, default=RESOURCE_DIR / "food-catalog-labels.json")
    parser.add_argument("--output", type=Path, default=RESOURCE_DIR / "foods-data.json")
    parser.add_argument("--provenance", type=Path, default=RESOURCE_DIR / "food-catalog-provenance.json")
    arguments = parser.parse_args()
    foods = build_catalog(load_source(arguments.source_zip), load_source(arguments.survey_zip, "survey"),
                          json.loads(arguments.labels.read_text(encoding="utf-8")))
    data = json.dumps(foods, ensure_ascii=False, separators=(",", ":")) + "\n"
    arguments.output.write_text(data, encoding="utf-8", newline="\n")
    details = provenance(foods, data.encode("utf-8"))
    arguments.provenance.write_text(json.dumps(details, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({name: details[name] for name in ["food_count", "catalog_bytes", "catalog_sha256", "foods_with_servings", "serving_count"]}))


if __name__ == "__main__":
    main()
