"""Read-only, server-side Open Food Facts catalogue, never a phone database.

Python 3.11+ standard library / SQLite FTS5. Import pinned complete JSONL exports
in committed batches; raw rows are retained losslessly (zlib), separate from
Luqma's personal foods and diary. No network calls occur during import.
"""
from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import json
import math
from pathlib import Path
import re
import sqlite3
import unicodedata
import zlib

OFF_EXPORT_URL = "https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz"
LICENCE = {"source": "Open Food Facts", "source_url": "https://world.openfoodfacts.org/",
           "database": "ODbL-1.0", "contents": "DbCL-1.0", "images": "CC-BY-SA-3.0",
           "terms_url": "https://world.openfoodfacts.org/terms-of-use"}
CODE = re.compile(r"[A-Za-z0-9_-]{1,180}\Z")
NUTRIENTS = {"kcal": "energy-kcal", "protein": "proteins", "carbs": "carbohydrates", "fat": "fat"}
MAX_LINE = 64 * 1024 * 1024
APPLICATION_ID = 0x4C554F46  # LUOF: refuse unrelated/personal SQLite databases.


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def normalized(value):
    value = unicodedata.normalize("NFKD", str(value).lower())
    for old, new in [("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ٱ", "ا"), ("ى", "ي"),
                     ("ة", "ه"), ("ـ", ""), ("ؤ", "و"), ("ئ", "ي"), ("ی", "ي"), ("ک", "ك")]:
        value = value.replace(old, new)
    for digits in ["٠١٢٣٤٥٦٧٨٩", "۰۱۲۳۴۵۶۷۸۹"]:
        value = value.translate(str.maketrans(digits, "0123456789"))
    return " ".join("".join(char if char.isalnum() else " "
                            for char in value if not unicodedata.category(char).startswith("M")).split())


def number(value):
    if isinstance(value, bool):
        return None
    try:
        value = float(value)
    except (TypeError, ValueError, OverflowError):
        return None
    return value if math.isfinite(value) and 0 <= value <= 100000 else None


def text(product, key):
    value = product.get(key)
    if isinstance(value, list) and all(isinstance(x, str) for x in value):
        value = ", ".join(value)
    return value.strip() if isinstance(value, str) and value.strip() else None


def structured_nutrients(raw, require_label_source=False):
    def amount(key, energy=False):
        row = raw.get(key)
        if not isinstance(row, dict) or (require_label_source and row.get("source") not in ("manufacturer", "packaging")):
            return None
        value = number(row.get("value"))
        if value is None:
            return None
        unit = str(row.get("unit", "")).lower()
        factor = ({"kcal": 1, "kj": 1 / 4.184} if energy else
                  {"g": 1, "mg": .001, "ug": .000001, "µg": .000001, "μg": .000001}).get(unit)
        return number(value * factor) if factor is not None else None
    return {"kcal": next((v for key in ("energy-kcal", "energy-kj", "energy")
                           if (v := amount(key, True)) is not None), None),
            "protein": amount("proteins"), "carbs": amount("carbohydrates"), "fat": amount("fat")}


def scale(values, factor):
    return {key: number(value * factor) if value is not None else None for key, value in values.items()}


def complete(values):
    return values is not None and all(values.get(key) is not None for key in NUTRIENTS)


def nutrition(product):
    """As-sold only; nullable values stay nullable and mass never becomes volume."""
    declaration = str(product.get("nutrition_data_per", "")).lower().replace(" ", "")
    declared_unit = "ml" if declaration == "100ml" else "g" if declaration == "100g" else None
    serving_text = text(product, "serving_size")
    quantity = number(product.get("serving_quantity"))
    portion_unit = product.get("serving_quantity_unit")
    if portion_unit not in ("g", "ml"):
        portion_unit = None
    match = re.search(r"([0-9]+(?:[.,][0-9]+)?)\s*(g|ml|gr|grams?)\b", serving_text or "", re.I)
    if match:
        quantity = number(match[1].replace(",", "."))
        portion_unit = "ml" if match[2].lower() == "ml" else "g"
    if quantity is None or quantity <= 0 or quantity > 10000:
        quantity = None
    # Legacy OFF's *_100g fields cover 100 g OR 100 ml; retain explicit liquid
    # label metadata. No package weight or portion count is used as density.
    unit = declared_unit or ("ml" if product.get("product_quantity_unit") == "ml" or portion_unit == "ml" else "g")
    empty = {key: None for key in NUTRIENTS}
    per100, serving = dict(empty), None
    if product.get("no_nutrition_data") in ("on", True):
        return unit, per100, serving, quantity, portion_unit, serving_text
    current = product.get("nutrition")
    if isinstance(current, dict):
        candidates = []
        for offset, raw in enumerate(current.get("input_sets", [])):
            if not isinstance(raw, dict) or raw.get("source") not in ("packaging", "manufacturer") or raw.get("preparation") != "as_sold":
                continue
            per = raw.get("per")
            if per not in ("100g", "100ml", "serving"):
                continue
            basis = "g" if per == "100g" else "ml" if per == "100ml" else raw.get("per_unit")
            basis = basis if basis in ("g", "ml") else None
            amount = 100 if per != "serving" else number(raw.get("per_quantity"))
            if amount is not None and not 0 < amount <= 10000:
                amount = None
            values = structured_nutrients(raw.get("nutrients", {}))
            candidates.append((raw, basis, amount, values, offset))
        candidates.sort(key=lambda x: (not complete(x[3]), x[0]["source"] != "manufacturer",
                                        x[1] != unit, x[0]["per"] == "serving", x[4]))
        if candidates:
            raw, basis, amount, values, _ = candidates[0]
            unit = basis or "serving"
            if basis and amount:
                per100 = scale(values, 100 / amount)
            if raw["per"] == "serving":
                serving = values
                if amount and basis and (quantity != amount or portion_unit != basis):
                    serving_text = format(amount, ".15g") + " " + basis
                quantity, portion_unit = amount, basis
            else:
                matching = next((x for x in candidates if x[0]["per"] == "serving" and
                                 x[0]["source"] == raw["source"] and x[1] == basis and complete(x[3])), None)
                if matching:
                    if matching[2] and matching[1] and (quantity != matching[2] or portion_unit != matching[1]):
                        serving_text = format(matching[2], ".15g") + " " + matching[1]
                    _, portion_unit, quantity, serving, _ = matching
        else:
            aggregate = current.get("aggregated_set", {})
            if isinstance(aggregate, dict) and aggregate.get("preparation") == "as_sold" and aggregate.get("per") in ("100g", "100ml"):
                per100 = structured_nutrients(aggregate.get("nutrients", {}), True)
                unit = "g" if aggregate["per"] == "100g" else "ml"
    else:
        values = product.get("nutriments", {})
        if not isinstance(values, dict):
            values = {}
        def legacy(suffix):
            kcal = number(values.get("energy-kcal_" + suffix))
            if kcal is None:
                kj = number(values.get("energy-kj_" + suffix))
                if kj is None and str(values.get("energy_unit", "")).lower() == "kj":
                    kj = number(values.get("energy_" + suffix))
                kcal = kj / 4.184 if kj is not None else None
                if kcal is None and str(values.get("energy_unit", "")).lower() == "kcal":
                    kcal = number(values.get("energy_" + suffix))
            return {"kcal": kcal, "protein": number(values.get("proteins_" + suffix)),
                    "carbs": number(values.get("carbohydrates_" + suffix)), "fat": number(values.get("fat_" + suffix))}
        per100 = legacy("100g")
        direct = legacy("serving")
        if complete(direct):
            serving = direct
    if not complete(serving) and quantity and portion_unit == unit:
        serving = scale(per100, quantity / 100)
    return unit, per100, serving, quantity, portion_unit, serving_text


def native_food(product, export_id, retrieved_at):
    code = product["code"]
    name = text(product, "product_name_ar") or text(product, "product_name") or text(product, "product_name_en")
    if not name:
        # Retained and indexed on the server, but no invented product name is
        # sent to the native Food model, whose name is mandatory.
        return None
    unit, values, direct, quantity, portion_unit, serving_text = nutrition(product)
    names = [value for key, value in product.items() if key.startswith("product_name") and isinstance(value, str)]
    food = {"id": "off:" + code, "name": name[:180], "unit": unit, "source": "OpenFoodFacts",
            "sourceId": code, "sourceDescription": "Open Food Facts · catalogue export · as sold",
            "aliases": " | ".join(dict.fromkeys(x for x in names if x != name)),
            "sourceMetadata": {"url": "https://world.openfoodfacts.org/product/" + code,
                               "databaseLicense": "ODbL-1.0", "contentsLicense": "DbCL-1.0",
                               "imageLicense": "CC-BY-SA-3.0", "exportID": export_id,
                               "retrievedAt": retrieved_at}}
    if text(product, "product_name_en"):
        food["nameEn"] = text(product, "product_name_en")[:180]
    if text(product, "brands"):
        food["brand"] = text(product, "brands")[:180]
    if code.isascii() and code.isdigit() and 8 <= len(code) <= 14:
        food["barcode"] = code
    for key, value in values.items():
        if value is not None:
            food[key] = value
    if complete(direct):
        food["servingNutrition"] = direct
    if serving_text:
        food["serving"] = serving_text[:180]
    elif direct and quantity and portion_unit:
        food["serving"] = format(quantity, ".15g") + " " + portion_unit
    if quantity:
        food["servingQuantity"] = quantity
    if portion_unit:
        food["servingUnit"] = portion_unit
    metadata = food["sourceMetadata"]
    try:
        modified = float(product.get("last_modified_t"))
        if not isinstance(product.get("last_modified_t"), bool) and math.isfinite(modified) and modified >= 0:
            metadata["lastModified"] = modified
    except (TypeError, ValueError, OverflowError):
        pass
    for key, target in [("countries_tags", "countries"), ("allergens_tags", "allergens")]:
        if isinstance(product.get(key), list):
            metadata[target] = [x for x in product[key] if isinstance(x, str)]
    if text(product, "ingredients_text"):
        metadata["ingredients"] = text(product, "ingredients_text")
    image = text(product, "image_front_url") or text(product, "image_url")
    if image and image.startswith("https://"):
        metadata["imageURL"] = image
    return food


def connect(path, readonly=False):
    path = Path(path).resolve()
    db = sqlite3.connect(path.as_uri() + "?mode=ro" if readonly else str(path), uri=readonly, timeout=15)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA busy_timeout=15000")
    app_id = db.execute("PRAGMA application_id").fetchone()[0]
    has_tables = db.execute("SELECT 1 FROM sqlite_master WHERE type='table' LIMIT 1").fetchone() is not None
    if app_id not in (0, APPLICATION_ID) or (has_tables and app_id != APPLICATION_ID) or (readonly and app_id != APPLICATION_ID):
        db.close()
        raise ValueError("This is not a Luqma public OFF catalogue; refusing unrelated database")
    if not readonly:
        db.execute("PRAGMA application_id=" + str(APPLICATION_ID))
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("PRAGMA synchronous=FULL")
        db.executescript("""
        CREATE TABLE IF NOT EXISTS imports(
            export_id TEXT PRIMARY KEY, source_url TEXT NOT NULL, export_date TEXT NOT NULL,
            sha256 TEXT NOT NULL, byte_size INTEGER NOT NULL, line_number INTEGER NOT NULL DEFAULT 0,
            records_read INTEGER NOT NULL DEFAULT 0, inserted INTEGER NOT NULL DEFAULT 0,
            updated INTEGER NOT NULL DEFAULT 0, unchanged INTEGER NOT NULL DEFAULT 0,
            rejected INTEGER NOT NULL DEFAULT 0, unnamed INTEGER NOT NULL DEFAULT 0,
            completed INTEGER NOT NULL DEFAULT 0, finalized INTEGER NOT NULL DEFAULT 0, retired INTEGER NOT NULL DEFAULT 0,
            started_at TEXT NOT NULL, updated_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS products(
            code TEXT PRIMARY KEY, raw_zlib BLOB NOT NULL, raw_sha256 TEXT NOT NULL,
            food_json TEXT, search_text TEXT NOT NULL, source_modified TEXT,
            export_id TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1);
        CREATE INDEX IF NOT EXISTS products_export ON products(export_id, active);
        CREATE VIRTUAL TABLE IF NOT EXISTS product_search USING fts5(
            search_text, content='products', content_rowid='rowid', tokenize='unicode61 remove_diacritics 2');
        CREATE TRIGGER IF NOT EXISTS products_ai AFTER INSERT ON products BEGIN
            INSERT INTO product_search(rowid, search_text) VALUES(new.rowid,new.search_text); END;
        CREATE TRIGGER IF NOT EXISTS products_ad AFTER DELETE ON products BEGIN
            INSERT INTO product_search(product_search,rowid,search_text) VALUES('delete',old.rowid,old.search_text); END;
        CREATE TRIGGER IF NOT EXISTS products_au AFTER UPDATE OF search_text ON products BEGIN
            INSERT INTO product_search(product_search,rowid,search_text) VALUES('delete',old.rowid,old.search_text);
            INSERT INTO product_search(rowid,search_text) VALUES(new.rowid,new.search_text); END;
        CREATE TABLE IF NOT EXISTS import_rejections(
            export_id TEXT NOT NULL, line_number INTEGER NOT NULL, reason TEXT NOT NULL,
            raw_zlib BLOB NOT NULL, PRIMARY KEY(export_id,line_number));
        """)
    return db


def file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def search_content(product):
    # No country filter: index every available language, brand and source ID.
    fields = [product["code"]]
    for key, value in product.items():
        if key == "brands" or key.startswith(("product_name", "generic_name")):
            if isinstance(value, str):
                fields.append(value)
    return normalized(" ".join(fields))


def import_dump(path, db_path, export_id, export_date, source_url=OFF_EXPORT_URL,
                expected_sha256=None, batch_size=250, stop_after=None, finalize=False):
    """Resume only the identical immutable file. Each batch + checkpoint is atomic.

    Gzip resume replays compressed input to a committed line; CPU/I/O cost is
    bounded in memory, not constant time. A plain .jsonl is faster to replay.
    --finalize is explicit: retire absent products only at fully verified EOF.
    """
    path = Path(path)
    if not 1 <= batch_size <= 10000 or not export_id.strip() or len(export_id) > 180:
        raise ValueError("Invalid batch size or export identity")
    dt.date.fromisoformat(export_date)
    digest = file_sha256(path)
    if expected_sha256 and digest.lower() != expected_sha256.lower():
        raise ValueError("Export SHA-256 mismatch")
    db = connect(db_path)
    try:
        found = db.execute("SELECT * FROM imports WHERE export_id=?", (export_id,)).fetchone()
        if found and (found["sha256"] != digest or found["byte_size"] != path.stat().st_size or
                      found["source_url"] != source_url or found["export_date"] != export_date):
            raise ValueError("Cannot resume a changed export; pin a new export_id")
        now = utc_now()
        if not found:
            with db:
                db.execute("INSERT INTO imports(export_id,source_url,export_date,sha256,byte_size,started_at,updated_at) VALUES(?,?,?,?,?,?,?)",
                           (export_id, source_url, export_date, digest, path.stat().st_size, now, now))
        state = dict(db.execute("SELECT * FROM imports WHERE export_id=?", (export_id,)).fetchone())
        if state["completed"]:
            if finalize and not state["finalized"]:
                with db:
                    _finalize(db, state)
                    _checkpoint(db, state)
                return dict(db.execute("SELECT * FROM imports WHERE export_id=?", (export_id,)).fetchone())
            return state
        opener = gzip.open if path.suffix == ".gz" else open
        processed, pending, reached_end = 0, 0, False
        try:
            with opener(path, "rb") as stream:
                line_number = 0
                while True:
                    raw = stream.readline(MAX_LINE + 1)
                    if not raw:
                        reached_end = True
                        break
                    line_number += 1
                    if len(raw) > MAX_LINE:
                        # Do not split a huge JSON object and corrupt checkpoints.
                        raise ValueError("Export row exceeds 64 MiB; inspect before import")
                    if line_number <= state["line_number"]:
                        continue
                    state["line_number"] = line_number
                    state["records_read"] += 1
                    try:
                        product = json.loads(raw)
                        if not isinstance(product, dict):
                            raise ValueError("not-an-object")
                        code = product.get("code")
                        if not isinstance(code, str) or not CODE.fullmatch(code):
                            raise ValueError("missing-or-invalid-string-code")
                        food = native_food(product, export_id, now)
                        # Refuse NaN/Infinity and lone surrogates before any
                        # accepted-record counters change. SQLite binds UTF-8;
                        # malformed source text belongs in raw rejections only.
                        canonical(product).encode("utf-8")
                        food_json = canonical(food) if food else None
                        if food_json is not None:
                            food_json.encode("utf-8")
                        raw_digest = hashlib.sha256(raw).hexdigest()
                        existing = db.execute("SELECT raw_sha256 FROM products WHERE code=?", (code,)).fetchone()
                        if existing is None:
                            state["inserted"] += 1
                        elif existing[0] == raw_digest:
                            state["unchanged"] += 1
                        else:
                            state["updated"] += 1
                        if food is None:
                            state["unnamed"] += 1
                        if existing is not None and existing[0] == raw_digest:
                            # Avoid re-compressing and rebuilding the FTS row
                            # for unchanged source content on daily snapshots.
                            db.execute("UPDATE products SET food_json=?,export_id=?,active=1 WHERE code=?",
                                       (food_json, export_id, code))
                        else:
                            db.execute("""INSERT INTO products(code,raw_zlib,raw_sha256,food_json,search_text,source_modified,export_id,active)
                                VALUES(?,?,?,?,?,?,?,1) ON CONFLICT(code) DO UPDATE SET
                                raw_zlib=excluded.raw_zlib,raw_sha256=excluded.raw_sha256,food_json=excluded.food_json,
                                search_text=excluded.search_text,source_modified=excluded.source_modified,
                                export_id=excluded.export_id,active=1""",
                                       (code, zlib.compress(raw), raw_digest, food_json,
                                        search_content(product), str(product.get("last_modified_t", "")), export_id))
                    except (ValueError, TypeError, UnicodeError, OverflowError) as error:
                        state["rejected"] += 1
                        reason = str(error) if isinstance(error, ValueError) else type(error).__name__
                        db.execute("INSERT OR REPLACE INTO import_rejections VALUES(?,?,?,?)",
                                   (export_id, line_number, reason[:200], zlib.compress(raw)))
                    pending += 1
                    processed += 1
                    if pending >= batch_size or (stop_after is not None and processed >= stop_after):
                        _checkpoint(db, state)
                        db.commit()
                        pending = 0
                    if stop_after is not None and processed >= stop_after:
                        break
                if reached_end:
                    state["completed"] = 1
                    if finalize:
                        # Rejected rows mean an incomplete snapshot; never retire
                        # good catalogue products on an incomplete import.
                        _finalize(db, state)
                _checkpoint(db, state)
                db.commit()
        except BaseException:
            db.rollback()
            raise
        db.execute("INSERT INTO product_search(product_search,rank) VALUES('integrity-check',1)")
        db.commit()
        if db.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise ValueError("SQLite integrity check failed")
        return dict(db.execute("SELECT * FROM imports WHERE export_id=?", (export_id,)).fetchone())
    finally:
        db.close()


def _checkpoint(db, state):
    keys = ["line_number", "records_read", "inserted", "updated", "unchanged", "rejected", "unnamed", "completed", "finalized", "retired"]
    db.execute("UPDATE imports SET " + ",".join(key + "=?" for key in keys) + ",updated_at=? WHERE export_id=?",
               [state[key] for key in keys] + [utc_now(), state["export_id"]])


def _finalize(db, state):
    if state["records_read"] == 0:
        raise ValueError("Cannot finalize an empty export")
    if not state["completed"] or state["rejected"]:
        raise ValueError("Cannot finalize an incomplete export or export with rejected rows")
    # Finalizing an old completed snapshot must never hide a newer import.
    newer = db.execute("SELECT 1 FROM imports WHERE started_at>? LIMIT 1", (state["started_at"],)).fetchone()
    if newer:
        raise ValueError("Cannot finalize an older export after a newer import")
    cursor = db.execute("UPDATE products SET active=0 WHERE active=1 AND export_id<>?", (state["export_id"],))
    state["retired"] = cursor.rowcount
    state["finalized"] = 1


def search(db, query, page=1, page_size=50):
    tokens = list(dict.fromkeys(normalized(query).split()))
    if not tokens or len(query) > 180 or len(tokens) > 16 or not 1 <= page <= 10000000 or not 1 <= page_size <= 100:
        raise ValueError("Invalid search or pagination")
    match = " AND ".join('"' + token.replace('"', '""') + '"*' for token in tokens)
    # Parameter binding + quoted tokens keep user input out of SQL/FTS syntax.
    rows = db.execute("""SELECT p.code,p.food_json FROM product_search JOIN products p ON p.rowid=product_search.rowid
                         WHERE product_search MATCH ? AND p.active=1 AND p.food_json IS NOT NULL
                         ORDER BY p.code LIMIT ? OFFSET ?""", (match, page_size + 1, (page - 1) * page_size)).fetchall()
    foods = [json.loads(row["food_json"]) for row in rows[:page_size]]
    return {"format": "luqma-off-catalog", "version": 1, "page": page, "page_size": page_size,
            "foods": foods, "next_page": page + 1 if len(rows) > page_size else None,
            "source_total": None, "licence": LICENCE}


def lookup(db, code):
    if not CODE.fullmatch(code):
        raise ValueError("Invalid product code")
    row = db.execute("SELECT food_json FROM products WHERE code=? AND active=1", (code,)).fetchone()
    return {"format": "luqma-off-catalog", "version": 1,
            "food": json.loads(row[0]) if row and row[0] else None, "licence": LICENCE}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--export-id", required=True)
    parser.add_argument("--export-date", required=True)
    parser.add_argument("--source-url", default=OFF_EXPORT_URL)
    parser.add_argument("--sha256", required=True, help="SHA-256 of the pinned compressed/plain input")
    parser.add_argument("--batch-size", type=int, default=250)
    parser.add_argument("--finalize", action="store_true", help="At verified EOF retire absent public records; refuses any rejected rows")
    args = parser.parse_args()
    print(canonical(import_dump(args.input, args.database, args.export_id, args.export_date,
                                args.source_url, args.sha256, args.batch_size, finalize=args.finalize)))


if __name__ == "__main__":
    main()
