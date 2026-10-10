"""Offline food data checks; no network, Xcode or large source archive needed."""
import copy
import hashlib
import json
import math
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Scripts"))
from import_usda_catalog import (LABEL_FIELDS, NUTRIENTS, SOURCE_COUNT,
                                SOURCE_SHA256, arabic_aliases,
                                convert_records, load_source)


class FoodCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        resources = ROOT / "Luqma" / "Resources"
        cls.data = (resources / "foods-data.json").read_bytes()
        cls.foods = json.loads(cls.data)
        cls.by_id = {food["id"]: food for food in cls.foods}
        cls.labels = json.loads((resources / "food-catalog-labels.json").read_text(encoding="utf-8"))
        cls.provenance = json.loads((resources / "food-catalog-provenance.json").read_text(encoding="utf-8"))

    def test_complete_unique_official_catalog_and_valid_per_100g_values(self):
        self.assertEqual(len(self.foods), SOURCE_COUNT)
        self.assertEqual(len(self.by_id), SOURCE_COUNT)
        for food in self.foods:
            with self.subTest(id=food["id"]):
                self.assertEqual(food["id"], "usda:" + food["sourceId"])
                self.assertEqual(food["source"], "USDA")
                self.assertEqual(food["unit"], "g")
                self.assertTrue(food["sourceDescription"].strip())
                for nutrient in NUTRIENTS:
                    value = food[nutrient]
                    self.assertIn(type(value), (int, float))
                    self.assertTrue(math.isfinite(value) and 0 <= value <= 100000)

    def test_existing_arabic_identity_aliases_and_servings_are_preserved(self):
        self.assertEqual(len(self.labels), 94)
        self.assertEqual([food["id"] for food in self.foods[:94]], [label["id"] for label in self.labels])
        for label in self.labels:
            with self.subTest(id=label["id"]):
                self.assertFalse(set(label) - LABEL_FIELDS)
                food = self.by_id[label["id"]]
                for key, value in label.items():
                    self.assertEqual(food[key], value)
                if "servingQuantity" in label:
                    for key in NUTRIENTS:
                        self.assertAlmostEqual(food["servingNutrition"][key], food[key] * label["servingQuantity"] / 100)

    def test_source_nutrients_include_explicit_zeroes_and_original_energy(self):
        # Exact values in the pinned official download, not macro-calorie estimates.
        egg = self.by_id["usda:171287"]
        self.assertEqual({key: egg[key] for key in NUTRIENTS}, {"kcal": 143, "protein": 12.6, "carbs": 0.72, "fat": 9.51})
        chicken = self.by_id["usda:171077"]
        self.assertEqual({key: chicken[key] for key in NUTRIENTS}, {"kcal": 120, "protein": 22.5, "carbs": 0, "fat": 2.62})
        olive_oil = self.by_id["usda:171413"]
        self.assertEqual(olive_oil["kcal"], 884)
        self.assertEqual(olive_oil["protein"], 0)
        self.assertEqual(olive_oil["carbs"], 0)

    def test_new_foods_keep_exact_source_names_and_arabic_search_expands_coverage(self):
        previous_ids = {label["id"] for label in self.labels}
        for food in self.foods:
            if food["id"] not in previous_ids:
                self.assertEqual(food["name"], food["sourceDescription"])
                self.assertEqual(food["nameEn"], food["sourceDescription"])
        self.assertGreater(sum("دجاج" in food.get("aliases", "") for food in self.foods), 100)
        self.assertGreater(sum("خبز" in food.get("aliases", "") for food in self.foods), 30)
        self.assertIn("خبز", arabic_aliases("Bread, pita, white"))
        self.assertNotIn("خبز", arabic_aliases("Pitanga, (surinam-cherry), raw"))
        self.assertNotIn("دجاج", arabic_aliases("Chickpeas, boiled"))

    def test_catalog_provenance_matches_pinned_source_and_generated_bytes(self):
        self.assertEqual(self.provenance["source_sha256"], SOURCE_SHA256)
        self.assertEqual(self.provenance["food_count"], SOURCE_COUNT)
        # Git checkout may use CRLF; generated content uses deterministic LF.
        normalized = self.data.replace(b"\r\n", b"\n")
        self.assertEqual(hashlib.sha256(normalized).hexdigest(), self.provenance["catalog_sha256"])
        self.assertEqual(self.provenance["license"], "CC0-1.0")

    def test_converter_rejects_unverified_archives(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "unverified.zip"
            source.write_bytes(b"unknown source contents")
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                load_source(source)

    def test_converter_preserves_source_values_and_rejects_broken_identity_or_nutrition(self):
        def sample():
            return {"fdcId": 123, "description": "Chicken, cooked",
                    "foodNutrients": [{"nutrient": {"id": nutrient_id, "unitName": "kcal" if key == "kcal" else "g"},
                                       "amount": {"kcal": 123, "protein": 20, "carbs": 0, "fat": 3}[key]}
                                      for key, nutrient_id in NUTRIENTS.items()]}
        label = {"id": "usda:123", "name": "دجاج", "aliases": "دجاج مطبوخ", "servingQuantity": 50, "servingUnit": "g"}
        food = convert_records([sample()], [label])[0]
        self.assertEqual(food["name"], "دجاج")
        self.assertEqual(food["carbs"], 0)
        self.assertEqual(food["kcal"], 123)
        self.assertEqual(food["servingNutrition"]["kcal"], 61.5)
        self.assertNotEqual(food["kcal"], food["protein"] * 4 + food["carbs"] * 4 + food["fat"] * 9)
        bad = sample()
        bad["foodNutrients"].pop()
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            convert_records([bad], [])
        bad = sample()
        bad["foodNutrients"][0]["amount"] = float("nan")
        with self.assertRaisesRegex(ValueError, "Invalid nutrient"):
            convert_records([bad], [])
        with self.assertRaisesRegex(ValueError, "Duplicate USDA"):
            convert_records([sample(), sample()], [])
        missing_label = copy.copy(label)
        missing_label["id"] = "usda:999"
        with self.assertRaisesRegex(ValueError, "absent"):
            convert_records([sample()], [missing_label])
        bad_label = dict(label, kcal=500)
        with self.assertRaisesRegex(ValueError, "nutritional fields"):
            convert_records([sample()], [bad_label])


if __name__ == "__main__":
    unittest.main()
