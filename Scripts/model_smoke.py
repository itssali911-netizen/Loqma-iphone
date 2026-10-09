#!/usr/bin/env python3
"""Exercise the exact app vision service on a Metal-capable Apple Silicon Mac.

This checks runtime integration and a mixed-food fixture, not calorie accuracy or
comparative performance. No user photograph is used or uploaded.
"""
import hashlib
import json
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'BuildOutput/model-runtime.json'
if platform.system() != 'Darwin' or platform.machine() != 'arm64':
    OUTPUT.write_text(json.dumps({'tested': False, 'reason': 'Requires Apple Silicon and Metal; iPhone SDK build is checked separately.'}, indent=2))
    print('Local model runtime check skipped: this runner is not Apple Silicon.')
    raise SystemExit(0)

with tempfile.TemporaryDirectory(prefix='luqma-model-check-') as directory:
    project = Path(directory)
    source = project / 'Sources/ModelCheck'
    resource = source / 'Resources'
    resource.mkdir(parents=True)
    for path in (ROOT / 'Luqma/Core').glob('*.swift'):
        shutil.copy2(path, source / path.name)
    service = (ROOT / 'Luqma/Services/VisionAnalyzer.swift').read_text().replace('Bundle.main.url', 'Bundle.module.url')
    (source / 'VisionAnalyzer.swift').write_text(service)
    for name in ['photo-foods.json', 'vision-model.json']:
        shutil.copy2(ROOT / 'Luqma/Resources' / name, resource / name)
    url = 'https://upload.wikimedia.org/wikipedia/commons/1/18/MyPlate_gov_Cultural_Food_(20241025-USDA-FNS-UNK-0017).jpg'
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'LuqmaAppValidation/1.1'}), timeout=90) as response:
        photo = response.read(12_000_000)
    if hashlib.sha256(photo).hexdigest() != '8c6f9cd2cdc344817c70091072a2c42f86c39ac83807040c184c137da1560b2d':
        raise RuntimeError('The public USDA photo fixture changed; inspect before updating its checksum.')
    (project / 'meal.jpg').write_bytes(photo)
    (project / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ModelCheck", platforms: [.macOS(.v14)], dependencies: [
 .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "2.30.6"),
 .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.6"),
 .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.1.6")
], targets: [.executableTarget(name: "ModelCheck", dependencies: [
 .product(name: "MLX", package: "mlx-swift"),
 .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
 .product(name: "MLXVLM", package: "mlx-swift-lm")
], resources: [.process("Resources")])], swiftLanguageVersions: [.v5])
''')
    shutil.copy2(ROOT / 'Scripts/ModelCheck.swift', source / 'Entry.swift')
    derived = project / 'DerivedData'
    command = ['xcodebuild', '-scheme', 'ModelCheck', '-destination', 'platform=macOS', '-configuration', 'Release', '-derivedDataPath', str(derived), 'CODE_SIGNING_ALLOWED=NO', 'build']
    with (ROOT / 'BuildOutput/model-runtime.log').open('wb') as log:
        result = subprocess.run(command, cwd=project, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode == 0:
            binary = derived / 'Build/Products/Release/ModelCheck'
            result = subprocess.run([str(binary), str(project / 'meal.jpg'), str(OUTPUT)], cwd=project, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print('\n'.join((ROOT / 'BuildOutput/model-runtime.log').read_text(errors='replace').splitlines()[-70:]))
        raise SystemExit(result.returncode)
    print(OUTPUT.read_text())
