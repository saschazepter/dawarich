#!/usr/bin/env python3
"""Builds lib/assets/admin1_supplement.geojson from geoBoundaries ADM1.

Natural Earth's admin-1 layer predates recent subdivision reforms in a number of
countries (Kenya's 2013 devolution to 47 counties, Nepal's 2015 provinces, ...).
geoBoundaries carries current boundaries with ISO 3166-2 codes, per-country
licensed. Only permissive licences are used here — Public Domain and CC BY.
ShareAlike and ODbL countries are deliberately excluded (see the skipped list).

Sources and licences: lib/assets/geoboundaries_sources.csv (pinned to one commit).

Run:
  python3 script/build_admin1_supplement.py
  npx mapshaper lib/assets/admin1_supplement_raw.geojson \\
    -simplify 4% keep-shapes \\
    -o format=geojson precision=0.001 lib/assets/admin1_supplement.geojson
  rm lib/assets/admin1_supplement_raw.geojson
"""

import csv, json, os, sys, unicodedata, collections, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMMIT = '9469f09'  # pinned geoBoundaries release commit
BASE = f'https://github.com/wmgeolab/geoBoundaries/raw/{COMMIT}/releaseData/gbOpen'

# permissive-licensed countries only (Public Domain / CC BY); see sources CSV
COUNTRIES = [('KE', 'KEN'), ('LY', 'LBY'), ('LB', 'LBN'), ('NP', 'NPL'),
             ('NO', 'NOR'), ('CI', 'CIV'), ('ZA', 'ZAF')]

# source-quirk fixes: (iso2, geoBoundaries shapeName) -> ISO 3166-2 code
OVERRIDES = {
    ('LY', 'Al Jufrah'): 'LY-JU',                              # shapeISO LY-JUU
    ('ZA', 'Nothern Cape'): 'ZA-NC',                           # source typo
    ('CI', "District Autonome D'Abidjan"): 'CI-AB',
    ('CI', 'District Autonome De Yamoussoukro'): 'CI-YM',
    ('CI', 'Valle Du Bandama'): 'CI-VB',
}


def normalize(value):
    ascii_value = unicodedata.normalize('NFKD', value).encode('ascii', 'ignore').decode()
    return ''.join(ch for ch in ascii_value.lower() if ch.isalnum())


def load_iso():
    by_code, by_name = collections.defaultdict(dict), collections.defaultdict(dict)
    path = os.path.join(ROOT, 'lib/assets/world_administrative_subdivisions.csv')
    for row in csv.DictReader(open(path)):
        code = row['subdivision_code']
        if code:
            by_code[row['country_code']][code] = row['subdivision_name']
            by_name[row['country_code']][normalize(row['subdivision_name'])] = code
    return by_code, by_name


def resolve(iso2, props, by_code, by_name):
    shape_iso, name = props.get('shapeISO'), props['shapeName']
    if (iso2, name) in OVERRIDES:
        return OVERRIDES[(iso2, name)]
    if shape_iso in by_code[iso2]:
        return shape_iso
    if f'{iso2}-{shape_iso}' in by_code[iso2]:
        return f'{iso2}-{shape_iso}'
    return by_name[iso2].get(normalize(name))


def main():
    by_code, by_name = load_iso()
    features, unresolved = [], []

    for iso2, iso3 in COUNTRIES:
        url = f'{BASE}/{iso3}/ADM1/geoBoundaries-{iso3}-ADM1.geojson'
        data = json.loads(urllib.request.urlopen(url).read())
        kept = 0
        for feature in data['features']:
            code = resolve(iso2, feature['properties'], by_code, by_name)
            if code is None:
                unresolved.append(f'{iso2}: {feature["properties"]["shapeName"]!r}')
                continue
            kept += 1
            features.append({'type': 'Feature',
                             'properties': {'iso_3166_2': code, 'name': by_code[iso2][code]},
                             'geometry': feature['geometry']})
        print(f'{iso2}: {kept}/{len(data["features"])} (ISO declares {len(by_code[iso2])})')

    out = os.path.join(ROOT, 'lib/assets/admin1_supplement_raw.geojson')
    json.dump({'type': 'FeatureCollection', 'features': features}, open(out, 'w'))
    print(f'\n{len(features)} features -> {out}')
    if unresolved:
        print('dropped (not in the ISO snapshot):', ', '.join(unresolved))


if __name__ == '__main__':
    main()
