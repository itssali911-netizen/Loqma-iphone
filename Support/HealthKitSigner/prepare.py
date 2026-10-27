"""Reproduce the reviewed community signer without installed account access."""
from __future__ import annotations
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parent
UPSTREAM = '902597564315442f00ab299dcc758ee0e13b8fa8'
CRATE_HASH = '649ccce64715f7b8f1e9eb330defc48d06d5d35eb8d13d17783533b02c67ba32'
ALLOWED = {
    'src-tauri/Cargo.toml', 'src-tauri/tauri.conf.json',
    'src-tauri/src/account.rs', 'src-tauri/src/secure_storage.rs',
    'src-tauri/src/lib.rs', 'src/App.tsx', 'src/update.ts',
    'vendor/isideload/src/dev/app_ids.rs',
    'vendor/isideload/src/sideload/healthkit.rs',
    'vendor/isideload/src/sideload/mod.rs',
    'vendor/isideload/src/sideload/sideloader.rs',
}

def safe_member(name: str) -> tuple[str, ...]:
    path = PurePosixPath(name)
    if ('\\' in name or path.is_absolute() or '..' in path.parts
            or not path.parts or path.parts[0] != 'isideload-0.5.0'
            or any(':' in part for part in path.parts)):
        raise ValueError('Unsafe source archive member')
    return path.parts[1:]

def prepare(output: Path) -> None:
    output = output.resolve()
    if output.exists():
        raise ValueError('Choose a fresh build directory; existing files are never removed.')
    manifest = json.loads((ROOT/'overlay-manifest.json').read_text('utf8'))
    if set(manifest) != ALLOWED:
        raise ValueError('Overlay file inventory is not the reviewed allowlist.')
    for name, digest in manifest.items():
        data = (ROOT/'overlay'/name).read_bytes()
        if hashlib.sha256(data).hexdigest() != digest:
            raise ValueError('Overlay checksum mismatch: '+name)
    subprocess.run(['git', '-c', 'core.autocrlf=false', 'clone', '--depth', '1', '--branch', 'v2.4.0',
                    'https://github.com/nab138/iloader.git', str(output)], check=True)
    head = subprocess.check_output(['git', '-C', str(output), 'rev-parse', 'HEAD'], text=True).strip()
    if head != UPSTREAM:
        raise ValueError('Publisher tag changed; source review must be repeated.')
    license_data = (output/'LICENSE').read_bytes()
    if license_data != (ROOT/'LICENSE-iloader-MIT.txt').read_bytes():
        raise ValueError('Publisher license differs from the reviewed copy.')
    with urllib.request.urlopen('https://static.crates.io/crates/isideload/isideload-0.5.0.crate', timeout=60) as response:
        data = response.read(4_000_001)
    if len(data) > 4_000_000 or hashlib.sha256(data).hexdigest() != CRATE_HASH:
        raise ValueError('Published signing-library checksum mismatch.')
    vendor = output/'vendor/isideload'
    vendor.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        members = archive.getmembers()
        if len(members) > 300:
            raise ValueError('Unexpected source archive inventory.')
        for member in members:
            parts = safe_member(member.name)
            if member.isdir():
                continue
            if not member.isfile() or not parts or member.size > 2_000_000:
                raise ValueError('Unexpected source archive type or size.')
            target = vendor.joinpath(*parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.extractfile(member).read())
    for name in sorted(manifest):
        target = output/name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((ROOT/'overlay'/name).read_bytes())
    # Exactly the same locked dependency now comes from the reviewed local
    # source. No version update or replacement of other locked packages.
    lock = output/'src-tauri/Cargo.lock'
    text = lock.read_text('utf8')
    old = ('name = "isideload"\nversion = "0.5.0"\n'
           'source = "registry+https://github.com/rust-lang/crates.io-index"\n'
           'checksum = "'+CRATE_HASH+'"\n')
    if text.count(old) != 1:
        raise ValueError('Unexpected signing-library lockfile entry.')
    lock.write_text(text.replace(old, 'name = "isideload"\nversion = "0.5.0"\n'), encoding='utf8', newline='\n')
    (output/'COMMUNITY-NOTICE.md').write_bytes((ROOT/'README-AR.md').read_bytes())
    (output/'source-provenance.json').write_text(json.dumps(dict(
        upstream_commit=head, isideload_crate_sha256=CRATE_HASH,
        overlays_sha256=manifest, authentication_performed=False,
        apple_account_modified=False, ipa_signed=False), indent=2)+'\n', encoding='utf8')
    print('Reviewed source prepared; no Apple account was accessed:', output)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    prepare(parser.parse_args().output)
