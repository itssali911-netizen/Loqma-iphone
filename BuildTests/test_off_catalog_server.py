"""Executable local catalogue tests, never evidence of a full OFF import."""
import gzip
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import urlopen
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Server/OFFCatalog"))
import catalog
import server


def product(code="00123456", name="حليب Milk", **changes):
    value = {"code": code, "product_name": name, "brands": "Example brand", "product_quantity_unit": "ml",
             "serving_size": "250 ml", "last_modified_t": 1700000000,
             "countries_tags": ["en:saudi-arabia", "en:france"], "private_unknown_future_field": {"keep": [1, 2]},
             "nutrition": {"input_sets": [{"source": "packaging", "preparation": "as_sold", "per": "100ml",
             "nutrients": {"energy-kcal": {"value": 62, "unit": "kcal"}, "proteins": {"value": 3.04, "unit": "g"},
             "carbohydrates": {"value": 0, "unit": "g"}, "fat": {"value": 3.28, "unit": "g"}}}]}}
    value.update(changes)
    return value


class OFFFullCatalogServerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.db = self.directory / "catalogue.sqlite"

    def dump(self, rows, name="export.jsonl.gz"):
        path = self.directory / name
        data = b"".join((catalog.canonical(row) + "\n").encode() for row in rows)
        if path.suffix == ".gz":
            with path.open("wb") as file:
                with gzip.GzipFile(fileobj=file, mode="wb", mtime=0) as stream:
                    stream.write(data)
        else:
            path.write_bytes(data)
        return path

    def ingest(self, path, export_id="test-only-synthetic", **options):
        return catalog.import_dump(path, self.db, export_id, "2026-11-03", expected_sha256=catalog.file_sha256(path), **options)

    def test_streaming_batch_resume_and_completed_rerun(self):
        path = self.dump([product(str(10000000 + i)) for i in range(12)])
        first = self.ingest(path, batch_size=3, stop_after=5)
        self.assertEqual((first["line_number"], first["inserted"], first["completed"]), (5, 5, 0))
        final = self.ingest(path, batch_size=2)
        self.assertEqual((final["records_read"], final["inserted"], final["completed"]), (12, 12, 1))
        again = self.ingest(path)
        self.assertEqual(again, final)
        with closing(catalog.connect(self.db, True)) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM products").fetchone()[0], 12)

    def test_resume_refuses_modified_export(self):
        path = self.dump([product()])
        self.ingest(path, stop_after=1)
        path = self.dump([product(name="Changed")])
        with self.assertRaisesRegex(ValueError, "changed export"):
            self.ingest(path)

    def test_bad_expected_hash_never_creates_database(self):
        path = self.dump([product()])
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            catalog.import_dump(path, self.db, "bad", "2026-11-03", expected_sha256="0" * 64)
        self.assertFalse(self.db.exists())

    def test_upserts_by_source_code_never_by_similar_name(self):
        self.ingest(self.dump([product(), product("00123457")]))
        second = self.ingest(self.dump([product(name="Changed milk"), product("00123457")], "next.jsonl.gz"), "next")
        self.assertEqual((second["inserted"], second["updated"], second["unchanged"]), (0, 1, 1))
        with closing(catalog.connect(self.db, True)) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM products").fetchone()[0], 2)
            self.assertEqual(catalog.lookup(db, "00123456")["food"]["name"], "Changed milk")

    def test_raw_bytes_and_unknown_fields_are_preserved(self):
        original = product()
        self.ingest(self.dump([original], "raw.jsonl"))
        with closing(catalog.connect(self.db, True)) as db:
            row = db.execute("SELECT raw_zlib,raw_sha256 FROM products").fetchone()
            raw = zlib.decompress(row[0])
            self.assertEqual(json.loads(raw), original)
            self.assertEqual(hashlib.sha256(raw).hexdigest(), row[1])

    def test_arabic_english_prefix_pagination_and_zero_are_real_values(self):
        self.ingest(self.dump([product(str(10000000 + i), "حَلِيب Milk " + str(i)) for i in range(5)]))
        with closing(catalog.connect(self.db, True)) as db:
            first = catalog.search(db, "حليب", page_size=2)
            second = catalog.search(db, "mil", page=2, page_size=2)
            self.assertEqual(first["next_page"], 2)
            self.assertEqual(len(second["foods"]), 2)
            self.assertFalse(set(x["id"] for x in first["foods"]) & set(x["id"] for x in second["foods"]))
            self.assertEqual(first["foods"][0]["carbs"], 0)
            self.assertEqual(first["foods"][0]["servingNutrition"]["kcal"], 155)
            self.assertEqual(first["foods"][0]["unit"], "ml")
            self.assertEqual(first["foods"][0]["sourceMetadata"]["countries"], ["en:saudi-arabia", "en:france"])

    def test_no_country_filter_and_unnamed_rows_retained(self):
        self.ingest(self.dump([product(countries_tags=["en:japan"]), product("00123457", "")]))
        with closing(catalog.connect(self.db, True)) as db:
            self.assertEqual(len(catalog.search(db, "Milk")["foods"]), 1)
            self.assertEqual(db.execute("SELECT count(*) FROM products").fetchone()[0], 2)
            self.assertIsNone(catalog.lookup(db, "00123457")["food"])

    def test_incomplete_nutrients_never_become_zero_or_complete_serving(self):
        row = product()
        del row["nutrition"]["input_sets"][0]["nutrients"]["proteins"]
        food = catalog.native_food(row, "test", "today")
        self.assertNotIn("protein", food)
        self.assertEqual(food["carbs"], 0)
        self.assertNotIn("servingNutrition", food)

    def test_unit_conversion_and_prepared_or_estimated_exclusion(self):
        row = product()
        nutrients = row["nutrition"]["input_sets"][0]["nutrients"]
        nutrients["energy-kcal"] = {"value": 418.4, "unit": "kJ"}
        nutrients["proteins"] = {"value": 3000, "unit": "mg"}
        food = catalog.native_food(row, "test", "today")
        self.assertAlmostEqual(food["kcal"], 100)
        self.assertEqual(food["protein"], 3)
        for key, value in [("source", "estimate"), ("source", "usda"), ("preparation", "prepared")]:
            changed = product()
            changed["nutrition"]["input_sets"][0][key] = value
            result = catalog.native_food(changed, "test", "today")
            self.assertFalse(set(catalog.NUTRIENTS) & set(result))
            self.assertNotIn("servingNutrition", result)

    def test_no_gram_millilitre_density_inference(self):
        row = product()
        row["nutrition"]["input_sets"][0]["per"] = "100g"
        food = catalog.native_food(row, "test", "today")
        self.assertEqual(food["unit"], "g")
        self.assertNotIn("servingNutrition", food)
        self.assertEqual(food["servingUnit"], "ml")

    def test_legacy_kj_requires_explicit_unit_and_missing_is_nil(self):
        row = product(nutrition=None, nutrition_data_per="100g", nutriments={"energy_100g": 418.4,
                     "proteins_100g": 2, "carbohydrates_100g": 0, "fat_100g": 1})
        food = catalog.native_food(row, "test", "today")
        self.assertNotIn("kcal", food)
        row["nutriments"]["energy_unit"] = "kJ"
        self.assertAlmostEqual(catalog.native_food(row, "test", "today")["kcal"], 100)
        row["nutriments"]["energy_unit"] = "kcal"
        self.assertEqual(catalog.native_food(row, "test", "today")["kcal"], 418.4)

    def test_absent_nutrition_marker_suppresses_stale_values(self):
        row = product(no_nutrition_data="on")
        food = catalog.native_food(row, "test", "today")
        self.assertFalse(set(catalog.NUTRIENTS) & set(food))
        self.assertNotIn("servingNutrition", food)

    def test_numeric_barcode_and_invalid_rows_are_rejected_with_raw_reason(self):
        path = self.dump([product(code=12345678), {"product_name": "Missing ID"}, product()])
        report = self.ingest(path)
        self.assertEqual((report["records_read"], report["inserted"], report["rejected"]), (3, 1, 2))
        with closing(catalog.connect(self.db, True)) as db:
            rejected = db.execute("SELECT reason,raw_zlib FROM import_rejections").fetchall()
            self.assertEqual(len(rejected), 2)
            self.assertTrue(all(x[0] == "missing-or-invalid-string-code" for x in rejected))

    def test_explicit_complete_snapshot_retirement_and_failed_import_guard(self):
        self.ingest(self.dump([product(), product("00123457")]))
        next_path = self.dump([product()], "next.jsonl.gz")
        report = self.ingest(next_path, "next", finalize=True)
        self.assertEqual(report["retired"], 1)
        with closing(catalog.connect(self.db, True)) as db:
            self.assertIsNone(catalog.lookup(db, "00123457")["food"])
            self.assertEqual(db.execute("SELECT count(*) FROM products").fetchone()[0], 2)
        bad = self.dump([product(), {"code": 12}], "bad.jsonl.gz")
        with self.assertRaisesRegex(ValueError, "rejected rows"):
            self.ingest(bad, "bad", finalize=True)

    def test_search_input_is_not_sql_or_fts_syntax(self):
        self.ingest(self.dump([product()]))
        with closing(catalog.connect(self.db, True)) as db:
            self.assertEqual(catalog.search(db, '" OR * DROP TABLE products --')["foods"], [])
            self.assertEqual(db.execute("PRAGMA quick_check").fetchone()[0], "ok")
            for query, page in [("", 1), ("x" * 181, 1), ("milk", 0)]:
                with self.assertRaises(ValueError):
                    catalog.search(db, query, page)

    def test_completed_export_can_finalize_but_old_export_cannot_hide_newer_data(self):
        first = self.dump([product(), product("00123457")])
        self.ingest(first)
        second = self.dump([product()], "new.jsonl.gz")
        self.ingest(second, "new")
        finished = self.ingest(second, "new", finalize=True)
        self.assertEqual((finished["finalized"], finished["retired"]), (1, 1))
        self.assertEqual(self.ingest(second, "new", finalize=True), finished)
        with self.assertRaisesRegex(ValueError, "older export"):
            self.ingest(first, finalize=True)

    def test_refuses_an_unrelated_personal_database(self):
        with closing(sqlite3.connect(self.db)) as database:
            database.execute("CREATE TABLE diary(personal TEXT)")
            database.execute("INSERT INTO diary VALUES('do-not-touch')")
            database.commit()
        with self.assertRaisesRegex(ValueError, "unrelated database"):
            self.ingest(self.dump([product()]))
        with closing(sqlite3.connect(self.db)) as database:
            self.assertEqual(database.execute("SELECT personal FROM diary").fetchone()[0], "do-not-touch")

    def test_original_real_snapshot_normalizes_source_nutrition(self):
        snapshot = json.loads((ROOT / "Scripts/Data/off-products-snapshot.json").read_text(encoding="utf-8"))
        rows = [json.loads(x["raw"])["product"] for x in snapshot["responses"] if x["included"]]
        report = self.ingest(self.dump(rows), "real-six-products-test-only")
        self.assertEqual(report["inserted"], 6)
        with closing(catalog.connect(self.db, True)) as db:
            milk = catalog.lookup(db, "6281007032261")["food"]
            self.assertEqual(milk["unit"], "ml")
            self.assertEqual(milk["servingNutrition"], {"kcal": 155, "protein": 7.6, "carbs": 12.8, "fat": 8.2})

    def test_http_search_lookup_error_and_export_are_real_routes(self):
        self.ingest(self.dump([product(), product("00123457", "أرز Rice")]))
        api = server.create_server(self.db, port=0, allow_export=True)
        worker = threading.Thread(target=api.serve_forever, daemon=True)
        worker.start()
        try:
            origin = "http://127.0.0.1:" + str(api.server_port)
            with urlopen(origin + "/v1/products?q=milk&page=1&page_size=50") as response:
                result = json.load(response)
                self.assertEqual(result["foods"][0]["sourceId"], "00123456")
            with urlopen(origin + "/v1/products/00123456") as response:
                self.assertEqual(json.load(response)["food"]["sourceMetadata"]["databaseLicense"], "ODbL-1.0")
            with self.assertRaises(HTTPError) as failure:
                urlopen(origin + "/v1/products?q=x&page=bad")
            self.assertEqual(failure.exception.code, 400)
            with urlopen(origin + "/v1/export") as response:
                rows = [json.loads(x) for x in gzip.decompress(response.read()).splitlines()]
            self.assertEqual(len(rows), 2)
            self.assertEqual(rows[0]["source"]["private_unknown_future_field"], {"keep": [1, 2]})
            self.assertIn("food", rows[0])
        finally:
            api.shutdown()
            api.server_close()
            worker.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
