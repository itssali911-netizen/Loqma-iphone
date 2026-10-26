"""Produce explicitly non-acceptance QA views from immutable source images.

No derivative is a production asset or an actual application capture. The
language, content and device safe areas differ, so no match score is reported.
"""
from pathlib import Path
from io import BytesIO
import hashlib
import json
from PIL import Image, ImageChops, ImageCms, ImageEnhance

HERE = Path(__file__).resolve().parent
NATIVE = HERE / 'native' / '07-search.png'
SOURCE = HERE / 'reference' / 'search-original.png'
OUT = HERE / 'baseline'
OUT.mkdir(exist_ok=True)

def srgb(image):
    profile = image.info.get('icc_profile')
    if profile:
        return ImageCms.profileToProfile(image.convert('RGB'), ImageCms.ImageCmsProfile(BytesIO(profile)), ImageCms.createProfile('sRGB'), outputMode='RGB')
    return image.convert('RGB')

source_image = Image.open(SOURCE)
native_image = Image.open(NATIVE)
source_image.verify()
native_image.verify()
source_image = Image.open(SOURCE)
native_image = Image.open(NATIVE)
# Pixel coordinates of the fourth (results) phone in the supplied image fill.
# These are a recorded raster ROI, not a Figma node / Auto Layout property.
roi = (1445, 352, 1820, 1164)
reference = srgb(source_image).crop(roi)
scale = reference.width / native_image.width
scaled_height = round(native_image.height * scale)
actual = srgb(native_image).resize((reference.width, scaled_height), Image.Resampling.LANCZOS)
actual = actual.crop((0, 0, reference.width, reference.height))
reference.save(OUT / 'search-reference-raster-roi.png')
actual.save(OUT / 'search-native-width-normalized.png')
Image.blend(reference, actual, .5).save(OUT / 'search-overlay-exploratory.png')
difference = ImageChops.difference(reference, actual)
ImageEnhance.Contrast(difference).enhance(3).save(OUT / 'search-difference-exploratory.png')
pair = Image.new('RGB', (reference.width * 2 + 12, reference.height), '#676C75')
pair.paste(reference, (0, 0))
pair.paste(actual, (reference.width + 12, 0))
pair.save(OUT / 'search-side-by-side.png')

def record(path):
    with Image.open(path) as im:
        dimensions = list(im.size)
    return dict(file=path.name, bytes=path.stat().st_size, dimensions=dimensions,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())

report = dict(
    purpose='Exploratory baseline only; no new UI implementation has been made',
    reference_node='2:10113',
    source_file='reference/search-original.png', source_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    source_dimensions=list(source_image.size), raster_roi=list(roi),
    roi_is_original_node_geometry=False,
    native_build='2.3 build59', native_commit='b9c0f7cfeb058472f33592ffbb61ed260bceecef',
    native_sha256=hashlib.sha256(NATIVE.read_bytes()).hexdigest(),
    native_original_dimensions=list(native_image.size), width_normalization_scale=scale,
    native_scaled_height=scaled_height, native_bottom_pixels_trimmed=scaled_height-reference.height,
    target_dimensions=list(reference.size), color_space='sRGB; embedded ICC converted when present',
    overlay_alpha=.5, difference='Absolute RGB difference, contrast x3 for inspection',
    production_assets_modified=False, original_capture_modified=False,
    matched_language=False, matched_data=False, matched_safe_areas=False, matched_viewport=False,
    comparable_for_acceptance=False, ssim_not_computed_reason='Different language, content, OS chrome and functional scope; a score would not measure implementation fidelity',
    findings=[
        'Reference is a generic fitness search with category chips and match dropdown; Luqma is real food search.',
        'Reference orange extends behind status bar; native sheet retains a black status area and rounded sheet top.',
        'Reference result cards have compact leading icons, labels/tags and trailing chevrons; native uses food/source/unit metadata and orange plus.',
        'Native header title placement, result density, icon shapes and chip geometry remain visually different.',
        'RTL adaptation, real catalog data and different viewport mean the overlay is diagnostic, not a pixel-perfect acceptance test.'
    ],
    artifacts=[record(p) for p in sorted(OUT.glob('*.png'))]
)
(OUT / 'comparison-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(json.dumps(dict(outputs=len(report['artifacts']), comparable_for_acceptance=False, original_capture_modified=False)))
