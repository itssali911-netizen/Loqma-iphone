#!/usr/bin/env python3
"""Export the exact mixed starter resources to JSON + read-only SQLite + ZIP.

The OFF subset and the user-supplied MFP subset retain separate provenance and
license statements. Missing nutrition remains SQL NULL / absent in source JSON.
"""
from __future__ import annotations
import argparse, hashlib, json, math, os, shutil, sqlite3, tempfile, unicodedata, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MFP_SOURCE = 'MyFitnessPal supplied IPA'
NUTRIENTS = ('kcal', 'protein', 'carbs', 'fat')

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False)+'\n', encoding='utf-8', newline='\n')

def normalized(value):
    value = unicodedata.normalize('NFKD', value.lower())
    for old, new in [('أ','ا'),('إ','ا'),('آ','ا'),('ٱ','ا'),('ى','ي'),('ة','ه'),('ـ',''),('ؤ','و'),('ئ','ي'),('ی','ي'),('ک','ك')]:
        value = value.replace(old, new)
    for digits in ['٠١٢٣٤٥٦٧٨٩','۰۱۲۳۴۵۶۷۸۹']:
        for index, digit in enumerate(digits): value = value.replace(digit, str(index))
    return ' '.join(''.join(c if c.isalnum() else ' ' for c in value if not unicodedata.combining(c)).split())

def runtime_id(food):
    return 'barcode:'+food['barcode'] if food.get('barcode') else food['id']

def checked_resources(resources):
    mfp_bytes=(resources/'mfp-foods-data.json').read_bytes()
    off_bytes=(resources/'foods-data.json').read_bytes()
    mfp_prov=json.loads((resources/'mfp-foods-provenance.json').read_text(encoding='utf-8'))
    off_prov=json.loads((resources/'food-catalog-provenance.json').read_text(encoding='utf-8'))
    if b'\r\n' in mfp_bytes or b'\r\n' in off_bytes: raise ValueError('Catalog must be canonical UTF-8/LF before exporting')
    if hashlib.sha256(mfp_bytes).hexdigest()!=mfp_prov['catalogSha256']: raise ValueError('MFP catalog/provenance digest mismatch')
    if hashlib.sha256(off_bytes).hexdigest()!=off_prov['catalog_sha256']: raise ValueError('OFF catalog/provenance digest mismatch')
    mfp=json.loads(mfp_bytes);off=json.loads(off_bytes)
    if len(mfp)!=744 or len(off)!=6: raise ValueError('Unexpected mixed starter counts')
    if any(f.get('source')!=MFP_SOURCE or f['id']!='mfp-bundled:'+f['sourceId'] for f in mfp): raise ValueError('MFP source identity mismatch')
    if any(f.get('source')!='OpenFoodFacts' or f['id']!='off:'+f['sourceId'] for f in off): raise ValueError('OFF source identity mismatch')
    if sum(len(f.get('portions',[])) for f in mfp)!=3830: raise ValueError('Unexpected MFP portion count')
    foods=sorted(mfp+off,key=lambda x:x['id'])
    if len({f['id'] for f in foods})!=750 or len({runtime_id(f) for f in foods})!=750: raise ValueError('Duplicate food identity')
    if any('user_id' in json.dumps(f) for f in foods): raise ValueError('Contributor identifiers must not be exported')
    return foods,mfp_prov,off_prov

def export_sqlite(path, foods, mfp_prov, off_prov):
    db=sqlite3.connect(path)
    db.executescript('''
        PRAGMA foreign_keys=ON;
        CREATE TABLE sources(source_key TEXT PRIMARY KEY, source_label TEXT NOT NULL, license_status TEXT NOT NULL, provenance_file TEXT NOT NULL);
        CREATE TABLE foods(
            food_id TEXT PRIMARY KEY, runtime_id TEXT UNIQUE NOT NULL, source_key TEXT NOT NULL REFERENCES sources(source_key), source_id TEXT NOT NULL,
            name TEXT NOT NULL, name_en TEXT, aliases TEXT, brand TEXT, barcode TEXT, reference_unit TEXT NOT NULL, reference_basis TEXT NOT NULL,
            kcal REAL, protein REAL, carbs REAL, fat REAL,
            serving_label TEXT, serving_quantity REAL, serving_unit TEXT, selected_portion_id TEXT,
            serving_kcal REAL, serving_protein REAL, serving_carbs REAL, serving_fat REAL, source_description TEXT,
            original_json TEXT NOT NULL);
        CREATE TABLE portions(
            food_id TEXT NOT NULL REFERENCES foods(food_id), portion_id TEXT NOT NULL, source_order INTEGER NOT NULL,
            kind TEXT NOT NULL, label TEXT NOT NULL, quantity REAL, unit_label TEXT, nutrition_multiplier REAL,
            kcal REAL, protein REAL, carbs REAL, fat REAL, PRIMARY KEY(food_id,portion_id));
        CREATE INDEX food_name ON foods(name);
        CREATE INDEX food_source ON foods(source_key,source_id);
        CREATE VIRTUAL TABLE food_search USING fts5(food_id UNINDEXED, normalized_name, normalized_brand, normalized_aliases, tokenize='unicode61 remove_diacritics 2');
    ''')
    db.executemany('INSERT INTO sources VALUES(?,?,?,?)',[
        ('off','Open Food Facts','ODbL-1.0 database; Database Contents License 1.0 individual contents','food-catalog-provenance.json'),
        ('mfp-bundled',MFP_SOURCE,'Not established from user-supplied artifact; personal reconstruction; not OFF/ODbL','mfp-foods-provenance.json')])
    for food in foods:
        mfp=food['source']==MFP_SOURCE
        unit=food['unit']
        basis='one selected declared serving; source-reference × portion multiplier' if mfp else '100 '+unit if unit in ('g','ml') else 'one declared serving'
        serving=food.get('servingNutrition') or {}
        values=[food['id'],runtime_id(food),'mfp-bundled' if mfp else 'off',food['sourceId'],
                food['name'],food.get('nameEn'),food.get('aliases'),food.get('brand'),food.get('barcode'),unit,basis,
                *[food.get(k) for k in NUTRIENTS],food.get('serving'),food.get('servingQuantity'),food.get('servingUnit'),food.get('selectedPortionID'),
                *[serving.get(k) for k in NUTRIENTS],food.get('sourceDescription'),json.dumps(food,ensure_ascii=False,separators=(',',':'),allow_nan=False)]
        db.execute('INSERT INTO foods VALUES('+','.join('?' for _ in values)+')',values)
        for index, portion in enumerate(food.get('portions',[])):
            n=portion.get('nutrition') or {}
            db.execute('INSERT INTO portions VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
                       [food['id'],portion['id'],index,'mfp-declared',portion['label'],portion['quantity'],portion['unit'],portion['nutritionMultiplier'],*[n.get(k) for k in NUTRIENTS]])
        # OFF's declared serving set is copied exactly; do not force it to match
        # a rounded per-100 nutrient set by recalculating a multiplier.
        if not mfp and food.get('serving'):
            db.execute('INSERT INTO portions VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
                       [food['id'],'off-declared-serving',0,'off-declared',food['serving'],food.get('servingQuantity'),food.get('servingUnit'),None,*[serving.get(k) for k in NUTRIENTS]])
        names=food['name']+' '+(food.get('nameEn') or '')
        db.execute('INSERT INTO food_search VALUES(?,?,?,?)',[food['id'],normalized(names),normalized(food.get('brand') or ''),normalized(food.get('aliases') or '')])
    db.commit()
    if db.execute('PRAGMA integrity_check').fetchall()!=[('ok',)]: raise ValueError('SQLite integrity check failed')
    if db.execute('PRAGMA foreign_key_check').fetchall(): raise ValueError('SQLite foreign key check failed')
    source_counts=dict(db.execute('SELECT source_key,COUNT(*) FROM foods GROUP BY source_key'))
    portion_counts=dict(db.execute('SELECT kind,COUNT(*) FROM portions GROUP BY kind'))
    if source_counts!={'mfp-bundled':744,'off':6} or portion_counts!={'mfp-declared':3830,'off-declared':5}: raise ValueError('SQLite row counts do not match source')
    unknown_foods=db.execute('SELECT COUNT(*) FROM foods WHERE kcal IS NULL OR protein IS NULL OR carbs IS NULL OR fat IS NULL').fetchone()[0]
    unknown_portions=db.execute('SELECT COUNT(*) FROM portions WHERE kcal IS NULL OR protein IS NULL OR carbs IS NULL OR fat IS NULL').fetchone()[0]
    if unknown_foods!=31 or unknown_portions!=94: raise ValueError('Unknown nutrition was changed')
    actual={row[0]:json.loads(row[1]) for row in db.execute('SELECT food_id,original_json FROM foods')}
    if actual!={f['id']:f for f in foods}: raise ValueError('SQLite JSON records differ from source')
    for food in foods:
        stored=db.execute('SELECT kcal,protein,carbs,fat FROM foods WHERE food_id=?',(food['id'],)).fetchone()
        if stored!=tuple(food.get(k) for k in NUTRIENTS): raise ValueError('SQLite nutrient mismatch')
        for portion in food.get('portions',[]):
            stored=db.execute('SELECT kcal,protein,carbs,fat FROM portions WHERE food_id=? AND portion_id=?',(food['id'],portion['id'])).fetchone()
            n=portion.get('nutrition') or {}
            if stored!=tuple(n.get(k) for k in NUTRIENTS): raise ValueError('SQLite portion nutrient mismatch')
    db.close()
    return dict(sqlite_integrity='ok',foreign_key_errors=0,food_count=750,source_counts=source_counts,
                portion_count=3835,portion_counts=portion_counts,incomplete_food_count=31,incomplete_portion_count=94,
                full_json_and_macro_roundtrip='exact',missing_nutrition='SQL NULL; source JSON fields remain absent')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resources',type=Path,default=ROOT/'Luqma'/'Resources')
    parser.add_argument('--output',type=Path,default=ROOT.parents[1]/'outputs'/'قاعدة-طعام-لقمة.zip')
    args=parser.parse_args()
    foods,mfp_prov,off_prov=checked_resources(args.resources)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='loqma-mixed-export-',dir=args.output.parent) as temporary:
        directory=Path(temporary)
        for name in ['foods-data.json','food-catalog-provenance.json','mfp-foods-data.json','mfp-foods-provenance.json']:
            shutil.copyfile(args.resources/name,directory/name)
        write_json(directory/'foods-mixed.json',foods)
        validation=export_sqlite(directory/'loqma-foods.sqlite',foods,mfp_prov,off_prov)
        validation['source_catalog_sha256']=dict(off=off_prov['catalog_sha256'],mfp=mfp_prov['catalogSha256'])
        write_json(directory/'validation.json',validation)
        attribution='''Mixed Loqma starter catalog — source-specific attribution

Open Food Facts: https://world.openfoodfacts.org/
Only the OFF subset is available under Open Database License 1.0 (ODbL-1.0).
Its individual contents are under Database Contents License 1.0.
Terms: https://world.openfoodfacts.org/terms-of-use
ODbL: https://opendatacommons.org/licenses/odbl/1-0/
DbCL: https://opendatacommons.org/licenses/dbcl/1-0/
No OFF product images are included. See food-catalog-provenance.json.

MyFitnessPal supplied IPA regional subset: explicitly supplied by the user for
personal Loqma reconstruction. Source data license was not established from
the supplied artifact; this subset is not relicensed as OFF, ODbL, or DbCL.
Original source package/member hashes are in mfp-foods-provenance.json.
No native app code, subscription patch, contributor user_id fields, private
service access, credentials, or Gemini API keys are included in this export.
The source label and original food identifiers remain distinct.
'''
        (directory/'ATTRIBUTION.txt').write_text(attribution,encoding='utf-8',newline='\n')
        readme='''قاعدة طعام لقمة — المصدران منفصلان

750 طعامًا محليًا: 744 سجلًا من ملف MyFitnessPal المرفق و6 منتجات Open Food Facts.
ليست هذه قاعدة MyFitnessPal العالمية ولا قاعدة Open Food Facts الكاملة.
3,830 حصة من الملف المرفق، و5 حصص معلنة لمنتجات OFF: المجموع 3,835.
تبقى التغذية المجهولة NULL في SQLite، والحقول الناقصة غائبة في JSON.
31 طعامًا و94 حصة تحتاج مراجعة الملصق وإكمال التغذية قبل تسجيلها.

foods-mixed.json: كل السجلات مع المصدر ومعرّف المصدر والحصص.
foods-data.json / mfp-foods-data.json: المصدران بصيغتهما المستخدمة في التطبيق.
ملفا provenance: الأدلة والبصمات وأساس التغذية وعدد السجلات والترخيص حسب المصدر.
loqma-foods.sqlite: جداول sources وfoods وportions، وفهرس food_search.
validation.json وsha256.json: تحقق الأعداد والقيم وبصمات الملفات.

reference_basis وreference_unit يحددان أساس أرقام الغذاء: بيانات MFP لحصة
معلنة مختارة، وبيانات OFF لكل 100 جم/مل بحسب الملصق. لا توجد فرضية كثافة
بين المل والجرام. حصص OFF تحتفظ بقيم الملصق؛ لا يُعاد اختراع معامل لها.
الفهرس SQLite يساعد البحث المحلي بالنصوص المطبّعة؛ ترتيب التطبيق الفعلي
واقتراحاته في كود لقمة، ولا يمثل معادلة MyFitnessPal السرية.

راجع ATTRIBUTION.txt: ترخيص OFF يخص قسمه فقط. ترخيص بيانات الملف المرفق
لم يثبت من فحص الحزمة، والمصدر محفوظ لاستعمال إعادة البناء الشخصي المطلوب.
'''
        (directory/'README-AR.txt').write_text(readme,encoding='utf-8',newline='\n')
        manifest={p.name:dict(bytes=p.stat().st_size,sha256=digest(p)) for p in sorted(directory.iterdir()) if p.is_file()}
        write_json(directory/'sha256.json',manifest)
        archive=directory/'catalog.zip'
        with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
            for p in sorted(directory.iterdir()):
                if p.is_file() and p!=archive:z.write(p,arcname=p.name)
        with zipfile.ZipFile(archive) as z:
            if z.testzip() is not None: raise ValueError('ZIP CRC verification failed')
            for name,item in manifest.items():
                data=z.read(name)
                if len(data)!=item['bytes'] or hashlib.sha256(data).hexdigest()!=item['sha256']:raise ValueError('ZIP member checksum mismatch')
        # Re-check after generation so a parallel rebuild cannot produce a
        # mixture of resource versions in the delivered archive.
        checked_resources(args.resources)
        for name in ['foods-data.json','food-catalog-provenance.json','mfp-foods-data.json','mfp-foods-provenance.json']:
            if digest(directory/name)!=digest(args.resources/name):raise ValueError('Source changed during export; retry')
        os.replace(archive,args.output)
    print(json.dumps(dict(output=str(args.output.resolve()),bytes=args.output.stat().st_size,sha256=digest(args.output),validation=validation),ensure_ascii=False,indent=2))

if __name__=='__main__':main()
