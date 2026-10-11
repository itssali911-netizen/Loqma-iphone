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
from import_usda_catalog import (CATALOG_COUNT, DATASETS, LABEL_FIELDS, NUTRIENTS,
                                SOURCE_COUNT, SURVEY_EXCLUDED_IDS, arabic_aliases,
                                convert_portions, convert_records, load_source)


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
        self.assertEqual(len(self.foods), CATALOG_COUNT)
        self.assertEqual(len(self.by_id), CATALOG_COUNT)
        self.assertNotIn("usda:2705383", self.by_id)
        for food in self.foods:
            with self.subTest(id=food["id"]):
                self.assertEqual(food["id"], "usda:" + food["sourceId"])
                self.assertEqual(food["source"], "USDA")
                self.assertEqual(food["unit"], "g")
                self.assertTrue(food["sourceDescription"].strip())
                self.assertLessEqual(len(food["name"]), 180)
                self.assertLessEqual(len(food["nameEn"]), 180)
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
                description = food["sourceDescription"]
                display = description if len(description) <= 180 else description[:177].rstrip() + "..."
                self.assertEqual(food["name"], display)
                self.assertEqual(food["nameEn"], display)
                if len(description) > 180:
                    self.assertIn(description, food["aliases"])
        self.assertGreater(sum("دجاج" in food.get("aliases", "") for food in self.foods), 100)
        self.assertGreater(sum("خبز" in food.get("aliases", "") for food in self.foods), 30)
        self.assertIn("خبز", arabic_aliases("Bread, pita, white"))
        self.assertNotIn("خبز", arabic_aliases("Pitanga, (surinam-cherry), raw"))
        self.assertNotIn("دجاج", arabic_aliases("Chickpeas, boiled"))

    def test_catalog_provenance_matches_pinned_source_and_generated_bytes(self):
        self.assertEqual(self.provenance["food_count"], CATALOG_COUNT)
        for source, expected in zip(self.provenance["sources"], DATASETS.values()):
            for key in ["source_sha256", "source_url", "source_zip_bytes", "source_food_count", "source_portion_count"]:
                self.assertEqual(source[key], expected[key])
            self.assertEqual(source["included_serving_count"] + source["excluded_portion_count"], source["source_portion_count"])
        self.assertEqual(sum(s["included_serving_count"] for s in self.provenance["sources"]), self.provenance["serving_count"])
        self.assertEqual([r["sourceId"] for r in self.provenance["sources"][1]["excluded_records"]],
                         [str(i) for i in sorted(SURVEY_EXCLUDED_IDS)])
        # Git checkout may use CRLF; generated content uses deterministic LF.
        normalized = self.data.replace(b"\r\n", b"\n")
        self.assertEqual(hashlib.sha256(normalized).hexdigest(), self.provenance["catalog_sha256"])
        self.assertEqual(len(normalized), self.provenance["catalog_bytes"])
        self.assertEqual(sum(bool(f.get("servings")) for f in self.foods), self.provenance["foods_with_servings"])
        self.assertEqual(sum(len(f.get("servings", [])) for f in self.foods), self.provenance["serving_count"])
        self.assertEqual(self.provenance["license"], "CC0-1.0")

    def test_converter_rejects_unverified_archives(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "unverified.zip"
            source.write_bytes(b"unknown source contents")
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                load_source(source)
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                load_source(source, "survey")

    def test_previous_sr_catalog_identity_labels_nutrients_and_precision_are_unchanged(self):
        # Removing the added choices reproduces the prior entire SR resource,
        # including all 7,793 identities and their exact nutrient precision.
        prior = [{k: v for k, v in food.items() if k != "servings"} for food in self.foods[:SOURCE_COUNT]]
        data = (json.dumps(prior, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
        self.assertEqual(hashlib.sha256(data).hexdigest(),
                         "28c166c2bfbdabd42a0a18ac8f1bb6d2babf706a5bec0a3643e3ecea6b1c0e34")

    def test_named_choices_keep_true_full_portion_weights_and_reject_unspecified_invalid_or_duplicate_choices(self):
        portions = [
            {"id": 1, "amount": 2, "measureUnit": {"name": "undetermined"}, "modifier": "tbsp", "gramWeight": 25, "sequenceNumber": 1},
            {"id": 2, "modifier": "10205", "portionDescription": "1 cup", "gramWeight": 158, "sequenceNumber": 2},
            {"id": 3, "modifier": "90000", "portionDescription": "Quantity not specified", "gramWeight": 150},
            {"id": 4, "amount": 0, "modifier": "cup", "gramWeight": 142},
            {"id": 5, "amount": 1, "modifier": "cup", "gramWeight": 0},
            {"id": 6, "portionDescription": "1 slice", "gramWeight": float("nan")},
            {"id": 7, "amount": 1, "modifier": "10205", "gramWeight": 50},
            {"id": 8, "portionDescription": "1 cup", "gramWeight": 10001},
            {"id": 9, "portionDescription": "1 cup", "gramWeight": True},
            {"id": 10, "portionDescription": "1 cup", "gramWeight": 158, "sequenceNumber": 3},
            {"id": 11, "amount": 2, "measureUnit": {"name": "tablespoon"}, "modifier": "chopped", "gramWeight": 10, "sequenceNumber": 4},
        ]
        expected = [{"id": "usda-portion:1", "label": "2 tbsp", "grams": 25},
                    {"id": "usda-portion:2", "label": "1 cup", "grams": 158},
                    {"id": "usda-portion:11", "label": "2 tablespoon chopped", "grams": 10}]
        self.assertEqual(convert_portions(portions), expected)
        self.assertEqual(convert_portions(list(reversed(portions))), expected)
        self.assertEqual(convert_portions(portions + portions), expected)

    def test_catalog_choices_have_valid_unique_ids_and_known_usda_weights(self):
        for food in self.foods:
            portions = food.get("servings", [])
            self.assertLessEqual(len(portions), 100)
            self.assertEqual(len({p["id"] for p in portions}), len(portions))
            self.assertEqual(len({(p["label"].casefold(), p["grams"]) for p in portions}), len(portions))
            for portion in portions:
                with self.subTest(food=food["id"], portion=portion["id"]):
                    self.assertEqual(set(portion), {"id", "label", "grams"})
                    self.assertTrue(portion["id"].startswith("usda-portion:"))
                    self.assertLessEqual(len(portion["id"]), 100)
                    self.assertTrue(portion["label"].strip() and len(portion["label"]) <= 180)
                    self.assertFalse(portion["label"].isdigit())
                    self.assertNotIn("not specified", portion["label"].casefold())
                    self.assertIn(type(portion["grams"]), (int, float))
                    self.assertTrue(math.isfinite(portion["grams"]) and 0 < portion["grams"] <= 10000)
        def weights(identifier):
            return {p["label"]: p["grams"] for p in self.by_id[identifier]["servings"]}
        self.assertEqual(weights("usda:171287")["1 large"], 50)
        self.assertEqual(weights("usda:169757")["1 cup"], 158)
        self.assertEqual(weights("usda:2707402")["1 tablespoon"], 15)
        self.assertEqual(weights("usda:2707408")["1 patty"], 17)

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
