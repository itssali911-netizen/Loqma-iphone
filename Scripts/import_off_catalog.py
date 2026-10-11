"""Rebuild a small, auditable OFF seed from pinned real product responses.

No network is needed to rebuild. Live product search covers the external OFF
database; this seed is not a copy of that database and is not a food accuracy
benchmark. Nutrition is copied from complete as-sold packaging/manufacturer
sets, preserving the stated g/ml/serving basis and source calorie values.
"""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCE_DIR = ROOT / "Luqma" / "Resources"
SNAPSHOT = ROOT / "Scripts" / "Data" / "off-products-snapshot.json"
NUTRIENTS = {"kcal": "energy-kcal", "protein": "proteins", "carbs": "carbohydrates", "fat": "fat"}
LICENSE = "ODbL-1.0"


def number(value):
    if isinstance(value, bool):
        return None
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) and 0 <= result <= 100000 else None


def text(product, key):
    value = product.get(key)
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        value = ", ".join(value)
    return value[:180] if isinstance(value, str) and value.strip() else None


def structured_nutrition(nutrients, require_label_source=False):
    def nutrient(key, energy=False):
        row = nutrients.get(key, {})
        value = number(row.get("value"))
        unit = str(row.get("unit", "")).lower()
        if value is None or (require_label_source and row.get("source") not in ("manufacturer", "packaging")):
            return None
        if energy:
            return value if unit == "kcal" else value / 4.184 if unit == "kj" else None
        return value * {"g": 1, "mg": 0.001, "µg": 0.000001, "μg": 0.000001, "ug": 0.000001}[unit] if unit in ("g", "mg", "µg", "μg", "ug") else None
    kcal = next((value for key in ("energy-kcal", "energy-kj", "energy") if (value := nutrient(key, True)) is not None), None)
    result = {"kcal": kcal, "protein": nutrient("proteins"), "carbs": nutrient("carbohydrates"), "fat": nutrient("fat")}
    return result if all(value is not None for value in result.values()) else None


def portion_size(value):
    match = re.search(r"([0-9]+(?:[.,][0-9]+)?)\s*(g|ml|gr|gram|grams)\b", value or "", re.IGNORECASE)
    if match and (amount := number(match[1].replace(",", "."))) is not None and 0 < amount <= 10000:
        return amount, "ml" if match[2].lower() == "ml" else "g"
    return None


def scaled(values, scale):
    return {key: value * scale for key, value in values.items()}


def convert_product(product):
    code = text(product, "code")
    name = text(product, "product_name_ar") or text(product, "product_name") or text(product, "product_name_en")
    if not code or not re.fullmatch(r"[A-Za-z0-9_-]+", code) or not name:
        raise ValueError("Missing product identity or name")
    label = text(product, "serving_size")
    portion = portion_size(label)
    if portion is None and (quantity := number(product.get("serving_quantity"))) is not None and 0 < quantity <= 10000 and product.get("serving_quantity_unit") in ("g", "ml"):
        portion = (quantity, product["serving_quantity_unit"])
    declared = (text(product, "nutrition_data_per") or "").lower().replace(" ", "")
    base = "ml" if declared == "100ml" else "g" if declared == "100g" else "ml" if product.get("product_quantity_unit") == "ml" or (portion and portion[1] == "ml") else "g"
    nutrition = product.get("nutrition")
    if not isinstance(nutrition, dict):
        raise ValueError("Current product nutrition schema is required")
    sets = []
    for offset, raw in enumerate(nutrition.get("input_sets", [])):
        if raw.get("source") not in ("manufacturer", "packaging") or raw.get("preparation") != "as_sold":
            continue
        values = structured_nutrition(raw.get("nutrients", {}))
        per = raw.get("per")
        if values is None or per not in ("100g", "100ml", "serving"):
            continue
        unit = "g" if per == "100g" else "ml" if per == "100ml" else raw.get("per_unit") if raw.get("per_unit") in ("g", "ml") else None
        quantity = 100 if per != "serving" else number(raw.get("per_quantity"))
        if quantity is not None and not 0 < quantity <= 10000:
            quantity = None
        sets.append(dict(values=values, source=raw["source"], unit=unit, quantity=quantity, serving=per == "serving", offset=offset))
    sets.sort(key=lambda item: (item["source"] != "manufacturer", item["unit"] != base, item["serving"], item["offset"]))
    per100 = direct = origin = None
    if sets:
        selected = sets[0]
        origin = selected["source"]
        base = selected["unit"] or "serving"
        if selected["quantity"] and selected["unit"]:
            per100 = scaled(selected["values"], 100 / selected["quantity"])
        serving = next((item for item in sets if item["serving"] and item["source"] == origin and item["unit"] == selected["unit"]), None)
        if serving:
            direct = serving["values"]
            if serving["quantity"] and serving["unit"]:
                own = (serving["quantity"], serving["unit"])
                if portion != own:
                    label = format(own[0], ".15g") + " " + own[1]
                portion = own
        if direct is None and portion and portion[1] == base and per100:
            direct = scaled(per100, portion[0] / 100)
    else:
        aggregate = nutrition.get("aggregated_set", {})
        if aggregate.get("preparation") == "as_sold" and aggregate.get("per") in ("100g", "100ml"):
            per100 = structured_nutrition(aggregate.get("nutrients", {}), require_label_source=True)
            if per100:
                base = "ml" if aggregate["per"] == "100ml" else "g"
                origin = "label/manufacturer aggregate"
                if portion and portion[1] == base:
                    direct = scaled(per100, portion[0] / 100)
    if per100 is None and direct is None:
        raise ValueError("Incomplete packaging/manufacturer nutrient set")
    if per100 and not all(number(value) is not None for value in per100.values()):
        per100 = None
        if direct is None:
            raise ValueError("Invalid normalized nutrient values")
    if per100 is None:
        base = "serving"
    english = text(product, "product_name_en")
    food = dict(id="off:" + code, name=name, unit=base, source="OpenFoodFacts", sourceId=code,
                sourceDescription="Open Food Facts · " + origin + " · as sold")
    if english:
        food["nameEn"] = english
    if brand := text(product, "brands"):
        food["brand"] = brand
    if code.isascii() and code.isdigit() and 8 <= len(code) <= 14:
        food["barcode"] = code
    food["aliases"] = " | ".join(value for key in ("product_name_ar", "product_name_en", "product_name") if (value := text(product, key)) and value not in (name, english))
    if per100:
        food.update(per100)
    if label:
        food["serving"] = label
    if portion:
        food["servingQuantity"], food["servingUnit"] = portion
    if direct:
        food["servingNutrition"] = direct
    return food


def load_snapshot(path=SNAPSHOT):
    snapshot = json.loads(Path(path).read_text(encoding="utf-8"))
    if snapshot.get("source") != "Open Food Facts" or snapshot.get("api_version") != "3.6":
        raise ValueError("Unexpected food source or API version")
    seen = set()
    for response in snapshot["responses"]:
        raw = response["raw"].encode("utf-8")
        if hashlib.sha256(raw).hexdigest() != response["response_sha256"]:
            raise ValueError("Product response SHA-256 mismatch")
        result = json.loads(raw)
        if result.get("status") != "success" or not response["source_url"].startswith("https://world.openfoodfacts.org/api/v3.6/product/"):
            raise ValueError("Unverified product endpoint or response")
        code = result["product"]["code"]
        if code in seen or "/" + code + ".json?" not in response["source_url"]:
            raise ValueError("Duplicate or mismatched source identity")
        seen.add(code)
    return snapshot


def generate(snapshot):
    foods = [convert_product(json.loads(item["raw"])["product"]) for item in snapshot["responses"] if item["included"]]
    data = (json.dumps(foods, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")
    provenance = dict(source="Open Food Facts", source_documentation="https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/",
                      license=LICENSE, contents_license="Database Contents License 1.0",
                      license_statement="https://world.openfoodfacts.org/terms-of-use", api_version="3.6",
                      retrieved_date=snapshot["retrieved_date"], source_snapshot="Scripts/Data/off-products-snapshot.json",
                      food_count=len(foods), catalog_bytes=len(data), catalog_sha256=hashlib.sha256(data).hexdigest(),
                      foods_with_servings=sum("servingNutrition" in food for food in foods),
                      serving_count=sum("servingNutrition" in food for food in foods),
                      sources=[{key: row[key] for key in ("source_url", "response_sha256", "included", "exclusion_reason") if key in row} for row in snapshot["responses"]],
                      nutrient_basis="Complete as-sold packaging/manufacturer sets, preserving explicit 100g, 100ml or serving basis. Source energy is retained; kJ is converted to kcal only when no explicit kcal is supplied. No USDA/estimate nutrient sets, missing-to-zero substitution or inferred liquid density.",
                      servings="Declared serving nutrient sets retain their source quantity/unit. If absent, a known same-unit label serving is calculated from per-100 nutrition. A missing serving is left unspecified for the user to define.",
                      scope="A small starter cache of six inspected products, not the complete OFF database. Submitted searches and barcode lookups query OFF live; saved OFF products work offline. Private manual foods and old diary totals are preserved separately. Photo categories contain no source nutrition.",
                      rebuild="python3 Scripts/import_off_catalog.py")
    return data, (json.dumps(provenance, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--snapshot", type=Path, default=SNAPSHOT)
    parser.add_argument("--output", type=Path, default=RESOURCE_DIR / "foods-data.json")
    parser.add_argument("--provenance", type=Path, default=RESOURCE_DIR / "food-catalog-provenance.json")
    args = parser.parse_args()
    data, provenance = generate(load_snapshot(args.snapshot))
    args.output.write_bytes(data)
    args.provenance.write_bytes(provenance)
    print(json.dumps({"food_count": len(json.loads(data)), "catalog_sha256": hashlib.sha256(data).hexdigest()}))


if __name__ == "__main__":
    main()
