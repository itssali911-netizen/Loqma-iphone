"""OFF source, reproducibility and nutrition-unit checks; no network required."""
import copy
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Scripts"))
from import_off_catalog import convert_product, generate, load_snapshot


def product():
    return {"code": "12345678", "product_name": "Example label", "nutrition": {"input_sets": [
        {"source": "packaging", "preparation": "as_sold", "per": "100g", "nutrients": {
            "energy-kcal": {"value": 125, "unit": "kcal"}, "proteins": {"value": 2, "unit": "g"},
            "carbohydrates": {"value": 0, "unit": "g"}, "fat": {"value": 3, "unit": "g"}}}]}}


class FoodCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        resources = ROOT / "Luqma/Resources"
        cls.data = (resources / "foods-data.json").read_bytes().replace(b"\r\n", b"\n")
        cls.foods = json.loads(cls.data)
        cls.by_id = {food["id"]: food for food in cls.foods}
        cls.snapshot = load_snapshot()
        cls.provenance = json.loads((resources / "food-catalog-provenance.json").read_text(encoding="utf-8"))

    def test_active_catalog_contains_six_unique_off_products_only(self):
        self.assertEqual(len(self.foods), 6)
        self.assertEqual(len(self.by_id), 6)
        for food in self.foods:
            self.assertEqual(food["source"], "OpenFoodFacts")
            self.assertEqual(food["id"], "off:" + food["sourceId"])
            self.assertIn(food["unit"], ("g", "ml"))
            self.assertLessEqual(len(food["name"]), 180)
            self.assertEqual(len({key for key in ("kcal", "protein", "carbs", "fat") if key in food}), 4)

    def test_hash_count_license_and_serving_provenance(self):
        self.assertEqual(self.provenance["catalog_sha256"], hashlib.sha256(self.data).hexdigest())
        self.assertEqual(self.provenance["catalog_bytes"], len(self.data))
        self.assertEqual(self.provenance["food_count"], 6)
        self.assertEqual(self.provenance["license"], "ODbL-1.0")
        self.assertEqual(self.provenance["foods_with_servings"], 5)
        self.assertEqual(self.provenance["serving_count"], 5)
        self.assertEqual(len(self.snapshot["responses"]), 13)
        self.assertEqual(sum(row["included"] for row in self.snapshot["responses"]), 6)
        self.assertTrue(all(row.get("exclusion_reason") for row in self.snapshot["responses"] if not row["included"]))

    def test_rebuild_exactly_reproduces_catalog_and_provenance(self):
        data, provenance = generate(self.snapshot)
        self.assertEqual(data, self.data)
        self.assertEqual(json.loads(provenance), self.provenance)

    def test_tampered_source_response_is_rejected(self):
        snapshot = copy.deepcopy(self.snapshot)
        snapshot["responses"][0]["raw"] += " "
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.json"
            path.write_text(json.dumps(snapshot), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                load_snapshot(path)

    def test_real_almarai_label_preserves_250ml_serving_and_source_macros(self):
        food = self.by_id["off:6281007032261"]
        self.assertEqual(food["unit"], "ml")
        self.assertEqual(food["servingQuantity"], 250)
        self.assertEqual(food["servingUnit"], "ml")
        self.assertEqual(food["servingNutrition"], {"kcal": 155, "protein": 7.6, "carbs": 12.8, "fat": 8.2})
        self.assertEqual(food["kcal"], 62)
        self.assertAlmostEqual(food["protein"], 3.04)

    def test_explicit_zero_and_source_kcal_are_preserved(self):
        food = convert_product(product())
        self.assertEqual(food["carbs"], 0)
        self.assertEqual(food["kcal"], 125)
        self.assertNotEqual(food["kcal"], food["protein"] * 4 + food["fat"] * 9)

    def test_missing_invalid_or_boolean_nutrients_are_never_zero_filled(self):
        for bad in (None, -1, float("nan"), float("inf"), True):
            raw = product()
            raw["nutrition"]["input_sets"][0]["nutrients"]["proteins"]["value"] = bad
            with self.subTest(value=bad), self.assertRaisesRegex(ValueError, "Incomplete"):
                convert_product(raw)

    def test_usda_estimated_and_prepared_nutrition_sets_are_excluded(self):
        for field, value in (("source", "usda"), ("source", "estimate"), ("preparation", "prepared")):
            raw = product()
            raw["nutrition"]["input_sets"][0][field] = value
            with self.subTest(field=field, value=value), self.assertRaisesRegex(ValueError, "Incomplete"):
                convert_product(raw)

    def test_gram_nutrition_does_not_infer_a_millilitre_serving(self):
        raw = product()
        raw["serving_size"] = "200 ml"
        food = convert_product(raw)
        self.assertEqual(food["unit"], "g")
        self.assertNotIn("servingNutrition", food)
        self.assertEqual(food["servingUnit"], "ml")

    def test_active_photo_categories_have_no_nutritional_reference_values(self):
        foods = json.loads((ROOT / "Luqma/Resources/photo-foods.json").read_text(encoding="utf-8"))
        legacy = json.loads((ROOT / "Tests/Fixtures/photo-foods-legacy.json").read_text(encoding="utf-8"))
        self.assertEqual([food["id"] for food in foods], [food["id"] for food in legacy])
        for food in foods:
            self.assertEqual(set(food), {"id", "name", "nameEn", "grams"})
            self.assertFalse({"kcal", "protein", "carbs", "fat"} & set(food))


if __name__ == "__main__":
    unittest.main()
