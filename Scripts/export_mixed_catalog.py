#!/usr/bin/env python3
"""Export the bundled mixed catalog, preserving source identity and unknowns."""
from __future__ import annotations
import argparse, hashlib, json, sqlite3, tempfile, zipfile
from contextlib import closing
from pathlib import Path

RESOURCES = Path(__file__).resolve().parents[1] / 'Luqma' / 'Resources'
FIELDS = ('kcal', 'protein', 'carbs', 'fat')

def export(destination: Path) -> dict:
    names = ('foods-data.json', 'food-catalog-provenance.json', 'mfp-foods-data.json',
             'mfp-foods-provenance.json', 'NOTICE.txt', 'LICENSES.txt')
    files = {name: (RESOURCES / name).read_bytes() for name in names}
    off, mfp = [json.loads(files[name]) for name in ('foods-data.json', 'mfp-foods-data.json')]
    off_provenance = json.loads(files['food-catalog-provenance.json'])
    mfp_provenance = json.loads(files['mfp-foods-provenance.json'])
    assert hashlib.sha256(files['foods-data.json']).hexdigest() == off_provenance['catalog_sha256']
    assert hashlib.sha256(files['mfp-foods-data.json']).hexdigest() == mfp_provenance['catalogSha256']
    foods = off + mfp
    assert len(off) == 6 and len(mfp) == 744 and len({x['id'] for x in foods}) == 750
    with tempfile.TemporaryDirectory(prefix='luqma-catalog-') as folder:
        database = Path(folder) / 'loqma-foods.sqlite'
        with closing(sqlite3.connect(database)) as con, con:
            con.executescript('''
                PRAGMA foreign_keys=ON;
                CREATE TABLE foods(id TEXT PRIMARY KEY,name TEXT NOT NULL,brand TEXT,aliases TEXT,
                    source TEXT NOT NULL,source_id TEXT NOT NULL,reference_unit TEXT NOT NULL,
                    kcal REAL,protein REAL,carbs REAL,fat REAL,default_portion_id TEXT);
                CREATE TABLE portions(food_id TEXT NOT NULL REFERENCES foods(id),id TEXT NOT NULL,
                    label TEXT NOT NULL,quantity REAL,unit TEXT,nutrition_multiplier REAL,
                    kcal REAL,protein REAL,carbs REAL,fat REAL,PRIMARY KEY(food_id,id));
                CREATE TABLE provenance(source TEXT PRIMARY KEY,document_json TEXT NOT NULL);
            ''')
            for food in foods:
                con.execute('INSERT INTO foods VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
                    [food['id'], food['name'], food.get('brand'), food.get('aliases'), food['source'],
                     food['sourceId'], food['unit'], *[food.get(k) for k in FIELDS], food.get('selectedPortionID')])
                choices = food.get('portions', [])
                if food.get('source') == 'OpenFoodFacts' and food.get('servingNutrition'):
                    choices = [dict(id='off-declared-serving',label=food['serving'],quantity=food['servingQuantity'],
                        unit=food['servingUnit'],nutrition=food['servingNutrition'])]
                for choice in choices:
                    nutrients = choice.get('nutrition') or {}
                    con.execute('INSERT INTO portions VALUES(?,?,?,?,?,?,?,?,?,?)',
                        [food['id'],choice['id'],choice['label'],choice.get('quantity'),choice.get('unit'),
                         choice.get('nutritionMultiplier'),*[nutrients.get(k) for k in FIELDS]])
            con.executemany('INSERT INTO provenance VALUES(?,?)',
                [('Open Food Facts',json.dumps(off_provenance,ensure_ascii=False)),
                 ('MyFitnessPal supplied IPA',json.dumps(mfp_provenance,ensure_ascii=False))])
            assert con.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
            assert not con.execute('PRAGMA foreign_key_check').fetchall()
            assert con.execute('SELECT count(*) FROM foods WHERE source=?',('MyFitnessPal supplied IPA',)).fetchone()[0] == 744
            assert con.execute('SELECT count(*) FROM portions WHERE food_id LIKE ?',('mfp-bundled:%',)).fetchone()[0] == 3830
            unknown = con.execute('SELECT count(*) FROM portions WHERE food_id LIKE ? AND kcal IS NULL',('mfp-bundled:%',)).fetchone()[0]
            assert unknown == 94
            for food in foods:
                row = con.execute('SELECT kcal,protein,carbs,fat FROM foods WHERE id=?',(food['id'],)).fetchone()
                assert tuple(food.get(k) for k in FIELDS) == row
                for choice in food.get('portions', []):
                    row = con.execute('SELECT kcal,protein,carbs,fat FROM portions WHERE food_id=? AND id=?',
                                      (food['id'],choice['id'])).fetchone()
                    assert tuple((choice.get('nutrition') or {}).get(k) for k in FIELDS) == row
        files['loqma-foods.sqlite'] = database.read_bytes()
        files['README-AR.txt'] = '''قاعدة لُقمة المختلطة — ٧٥٠ طعامًا

يتضمن التطبيق ٦ منتجات أولية من Open Food Facts و٧٤٤ طعامًا من ملف MyFitnessPal الذي قدّمه المستخدم.
يضم الملف ٣٬٨٣٠ حصة من MyFitnessPal و٥ حصص معلنة من منتجات Open Food Facts.
تبقى ٩٤ حصة ناقصة التغذية بقيم NULL؛ لا تُعتبر صفرًا. ٣١ طعامًا ناقص المرجع الغذائي.
ملفا JSON هما بيانات التطبيق الفعلية؛ SQLite نسخة مستقلة للاطلاع والتطوير.
قيمة reference_unit للحصص هي serving؛ لا تُعامل تلقائيًا كـ١٠٠ غرام.
Open Food Facts له ترخيص ODbL وDatabase Contents License؛ انظر ملفات المصدر.
بيانات MyFitnessPal منفصلة ومن ملف المستخدم؛ لم يُثبت ترخيص إعادة توزيعها من الملف، ولا تمثل القاعدة العالمية كاملة.
لا يحتوي هذا الأرشيف على مفتاح Gemini أو بيانات الحساب أو الصور أو السجل الشخصي.
'''.encode('utf-8')
        files['SHA256SUMS.txt'] = ''.join(hashlib.sha256(data).hexdigest()+'  '+name+'\n'
                                        for name,data in sorted(files.items())).encode()
        destination.parent.mkdir(parents=True,exist_ok=True)
        staged = destination.with_suffix('.staging.zip')
        with zipfile.ZipFile(staged,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
            for name,data in sorted(files.items()): archive.writestr(name,data)
        with zipfile.ZipFile(staged) as archive:
            assert archive.testzip() is None
            assert all(archive.read(name) == data for name,data in files.items())
        staged.replace(destination)
    return dict(food_count=750,mfp_food_count=744,off_food_count=6,mfp_portion_count=3830,
                off_declared_portion_count=5,unknown_mfp_portion_count=unknown,integrity_check='ok',
                foreign_key_check=[],bytes=destination.stat().st_size,sha256=hashlib.sha256(destination.read_bytes()).hexdigest())

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination',type=Path)
    args = parser.parse_args()
    print(json.dumps(export(args.destination),indent=2))
