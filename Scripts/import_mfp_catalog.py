#!/usr/bin/env python3
"""Convert the explicitly supplied IPA's regional food seed, without execution.

No MyFitnessPal network/API, credentials, contributor IDs or patched code is
used. The prepared catalog is separate from OFF and keeps its actual provenance.
"""
from __future__ import annotations
import argparse, collections, hashlib, json, math, re, zipfile
from pathlib import Path

EXPECTED_IPA_SHA256 = '5b82d27fb27ae7daa754743f74d4d3ad358bd126439e4e2fa964f322651823d5'
MEMBER = 'Payload/MyFitnessPal.app/most_logged_items_by_country.items.json'
EXPECTED_MEMBER_SHA256 = 'eb82813e0637ea9781c0de280b0db3658acf6c4fec8a44e176f72d8dff0822e5'
SOURCE = 'MyFitnessPal supplied IPA'
SEARCH_TERMS = {
    'milk': ['حليب'], 'rice': ['أرز', 'رز'], 'bread': ['خبز'],
    'chicken': ['دجاج'], 'egg': ['بيض'], 'eggs': ['بيض'],
    'oat': ['شوفان'], 'oats': ['شوفان'], 'oatmeal': ['شوفان'],
    'yogurt': ['زبادي'], 'yoghurt': ['زبادي'], 'cheese': ['جبن', 'جبنة'],
    'beef': ['لحم بقري'], 'banana': ['موز'], 'bananas': ['موز'],
    'apple': ['تفاح'], 'apples': ['تفاح'], 'potato': ['بطاطس', 'بطاطا'],
    'potatoes': ['بطاطس', 'بطاطا'], 'tomato': ['طماطم'], 'tomatoes': ['طماطم'],
    'fish': ['سمك'], 'salmon': ['سلمون'], 'tuna': ['تونة'],
    'almond': ['لوز'], 'almonds': ['لوز'], 'peanut': ['فول سوداني'],
    'peanuts': ['فول سوداني'], 'butter': ['زبدة'], 'oil': ['زيت'],
    'sugar': ['سكر'], 'coffee': ['قهوة'], 'tea': ['شاي'],
    'pasta': ['مكرونة', 'معكرونة'], 'lentil': ['عدس'], 'lentils': ['عدس'],
}

def search_aliases(name):
    # Independent query metadata, not translation or source nutrient content.
    # Whole English words only: "tea" must not accidentally match "steak".
    words = set(re.findall(r'[a-z]+', name.lower()))
    result = []
    for word, values in SEARCH_TERMS.items():
        if word in words:
            for value in values:
                if value not in result: result.append(value)
    return ';'.join(result)

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''): h.update(chunk)
    return h.hexdigest()

def valid_number(value, positive=False, maximum=100000):
    return isinstance(value, (float, int)) and not isinstance(value, bool) and math.isfinite(value) and (value > 0 if positive else value >= 0) and value <= maximum

def reference_nutrition(record):
    n = record.get('nutritional_contents', {})
    energy = n.get('energy', {})
    if not isinstance(energy, dict) or energy.get('unit') != 'calories': return None
    result = dict(kcal=energy.get('value'), protein=n.get('protein'), carbs=n.get('carbohydrates'), fat=n.get('fat'))
    return result if all(valid_number(v) for v in result.values()) else None

def transform(records):
    foods = []; omitted = []; incomplete_foods = []; incomplete_portions = 0
    for key, record in records.items():
        if record.get('id') != key or not isinstance(key, str) or not key or len(key) > 180:
            raise ValueError('Source record identity is invalid')
        name = record.get('description')
        if not isinstance(name, str) or not name.strip() or len(name) > 240:
            raise ValueError('Source food name is invalid; refusing silent record loss')
        if record.get('public') is not True or record.get('deleted') is not False:
            raise ValueError('Source is not an undeleted public record')
        base = reference_nutrition(record)
        if base is None: incomplete_foods.append(key)
        portions = []
        for source in record.get('serving_sizes', []):
            sid = source.get('id'); quantity = source.get('value'); unit = source.get('unit')
            multiplier = source.get('nutrition_multiplier'); index = source.get('index')
            reasons = []
            if not isinstance(sid, str) or not sid or len(sid) > 100: reasons.append('invalid_id')
            if not valid_number(quantity, positive=True, maximum=10000): reasons.append('invalid_quantity')
            if not isinstance(unit, str) or not unit.strip() or len(unit) > 240: reasons.append('invalid_unit_label')
            if not valid_number(multiplier, positive=True): reasons.append('invalid_multiplier')
            if not isinstance(index, int) or isinstance(index, bool) or index < 0: reasons.append('invalid_index')
            if reasons:
                omitted.append(dict(foodId=key, servingId=sid, reasons=reasons)); continue
            label = f'{quantity:g} {unit.strip()}'
            if len(label) > 240:
                omitted.append(dict(foodId=key, servingId=sid, reasons=['invalid_display_label'])); continue
            n = {field: value * multiplier for field, value in base.items()} if base is not None else None
            if n is not None and not all(valid_number(v) for v in n.values()): n = None
            if n is None: incomplete_portions += 1
            choice = dict(id=sid, label=label, quantity=quantity, unit=unit.strip(), nutritionMultiplier=multiplier)
            if n is not None: choice['nutrition'] = n
            portions.append((index, choice))
        portions.sort(key=lambda item: (item[0], item[1]['id']))
        choices = [p for _, p in portions]
        food = dict(id='mfp-bundled:' + key, name=name.strip(), unit='serving',
                    source=SOURCE, sourceId=key,
                    sourceDescription='User-supplied MyFitnessPal 26.33.0 IPA regional suggestions; not the global database',
                    portions=choices)
        brand = record.get('brand_name')
        if isinstance(brand, str) and brand.strip(): food['brand'] = brand.strip()
        aliases = search_aliases(name)
        if aliases: food['aliases'] = aliases
        if choices:
            chosen = choices[0]
            food.update(selectedPortionID=chosen['id'], serving=chosen['label'],
                        servingQuantity=chosen['quantity'], servingUnit=chosen['unit'])
            if chosen.get('nutrition') is not None:
                food.update(chosen['nutrition']); food['servingNutrition'] = chosen['nutrition']
        foods.append(food)
    return foods, dict(sourceFoodCount=len(records), foodCount=len(foods),
                       sourcePortionCount=sum(len(x.get('serving_sizes', [])) for x in records.values()),
                       portionCount=sum(len(x['portions']) for x in foods),
                       completeFoodCount=len(foods)-len(incomplete_foods), incompleteFoodCount=len(incomplete_foods),
                       completePortionCount=sum('nutrition' in p for x in foods for p in x['portions']),
                       incompletePortionCount=incomplete_portions, omittedPortionCount=len(omitted),
                       incompleteFoodIDs=incomplete_foods, omittedPortions=omitted)

def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False)+'\n', encoding='utf-8', newline='\n')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ipa', type=Path, required=True)
    parser.add_argument('--output-directory', type=Path, default=Path(__file__).resolve().parents[1]/'Luqma'/'Resources')
    args = parser.parse_args()
    if digest(args.ipa) != EXPECTED_IPA_SHA256: raise ValueError('IPA digest does not match the explicitly inspected source')
    with zipfile.ZipFile(args.ipa) as z:
        data = z.read(MEMBER)
        if hashlib.sha256(data).hexdigest() != EXPECTED_MEMBER_SHA256: raise ValueError('Food member digest does not match')
        records = json.loads(data)
        if len(records) != 744: raise ValueError('Unexpected regional seed count')
        foods, counts = transform(records)
        provenance = dict(schemaVersion=1, source=SOURCE, sourceVersion='26.33.0', sourceBuild='78122',
                          ipaSha256=EXPECTED_IPA_SHA256, sourceMember=MEMBER, sourceMemberSha256=EXPECTED_MEMBER_SHA256,
                          sourceMemberBytes=len(data), sourceZipHeaderOffset=z.getinfo(MEMBER).header_offset,
                          counts=counts, licenseStatus='Not established from supplied artifact; not Open Food Facts / ODbL data',
                          contributorIDs='user_id fields intentionally omitted',
                          nutritionBasis='Source reference nutrients multiplied by each declared serving nutrition_multiplier; no universal 100 g/ml basis inferred',
                          incompleteNutrition='Missing/invalid nutrients remain absent. Labeled portions remain available for explicit user correction.',
                          defaultServing='Lowest source index among structurally valid source portions',
                          verification='Source verified flags are not imported as independent nutrition validation',
                          searchAliases='Independent Luqma Arabic generic food search terms matched to whole English words in original descriptions; not complete translations, not source nutrition, and brand names are not translated',
                          searchAliasFoodCount=sum('aliases' in f for f in foods),
                          dataCoverage=dict(distinctDescriptionCount=len({x['description'] for x in records.values()}),
                                            sourceArabicDescriptionCount=sum(bool(re.search(r'[\u0600-\u06ff]',x['description'])) for x in records.values()),
                                            sourceBrandCount=sum(bool(x.get('brand_name')) for x in records.values()),
                                            sourceCountryCounts=dict(collections.Counter(x['country_code'] for x in records.values()))))
    args.output_directory.mkdir(parents=True, exist_ok=True)
    resource = args.output_directory/'mfp-foods-data.json'
    write(resource, foods)
    provenance['catalogSha256'] = digest(resource)
    write(args.output_directory/'mfp-foods-provenance.json', provenance)
    print(json.dumps({k: v for k, v in counts.items() if not isinstance(v, list)}, indent=2))

if __name__ == '__main__': main()
