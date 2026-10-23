#!/usr/bin/env python3
"""Measure the actual optimized Luqma UI on one disposable Simulator.

This infrastructure never asserts a performance improvement or a physical FPS.
Run against the integrated approved-UI baseline, then the optimization revision,
with the same fixture, harness, Xcode, runtime, model and Release/-O settings.
DEBUG is explicitly defined in this test build solely to enable isolated fixture
seeding. The shipped Release application does not receive this definition.

The app must seed its normal protected diary ONCE when passed
-loqma-performance-fixture, and expose the agreed accessibility identity on an
existing container. Subsequent launches must use the normal file decode path.
No preview-screen flags, API credentials, remote AI calls or existing devices.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shlex
import statistics
import subprocess
import sys
import time
import uuid

from build_ios import BuildError, public_environment, require_mac
from simulator_support import prepare_created_simulator
from ui_preview import DEVICE_TYPE, select_runtime
from vision_compat import apply_vision_compat


ROOT = Path(__file__).resolve().parent.parent
FIXTURE_IDENTITY = 'v1|entries=5000|days=7|today=800|seed=20261021'
TESTS = (
    'testResponsiveProcessLaunch',
    'testWarmForegroundResume',
    'testTabRoundTrip',
    'testHomeFoodLoggingRoundTrip',
    'testFoodSearchToQuantity',
    'testHomeToSevenDayCalorieDetails',
    'testHomeFitnessProfileAssessmentEntry',
    'testFitnessProfileToPersonalizedPlan',
    'testExpandedDiaryScroll',
)
LIMITATIONS = [
    'Simulator measurements are not physical iPhone measurements or 120Hz verification.',
    'Shared macOS CI host scheduling can affect timing, CPU and memory observations.',
    'Clock metrics around UI controls include XCUITest/accessibility overhead.',
    'Terminated-process launch after warm-up is not reboot-cold or cold-file-cache launch.',
    'No observed FPS or frame-time distribution is derived from screenshots or wall time.',
    'No battery/thermal/physical camera/remote AI speed/leak-freedom claim is made.',
    'Synthetic valid diary data exercises production views and persistence, not real user meals.',
    'The optimized Release test build includes DEBUG solely for the isolated fixture hook.',
]

CORE_BENCHMARK = r'''import Foundation
import CryptoKit
import Darwin

@main struct LuqmaCorePerformanceProbe {
    static func usage() -> (cpu: Double, peak: Int64) {
        var value = rusage()
        getrusage(RUSAGE_SELF, &value)
        let user = Double(value.ru_utime.tv_sec) + Double(value.ru_utime.tv_usec) / 1_000_000
        let system = Double(value.ru_stime.tv_sec) + Double(value.ru_stime.tv_usec) / 1_000_000
        return (user + system, Int64(value.ru_maxrss))
    }
    static func main() throws {
        let count = 5000
        let days = ["2026-10-21", "2026-10-20", "2026-10-19", "2026-10-18", "2026-10-17", "2026-10-16", "2026-10-15"]
        let food = Food(catalogID: "performance-core-oats", name: "Performance Core Oats", unit: .serving,
                        nutrition: Nutrition(kcal: 100, protein: 10, carbs: 15, fat: 0),
                        serving: "1 serving", source: "Your food")
        var snapshot = DiarySnapshot()
        snapshot.language = .en
        snapshot.entries.reserveCapacity(count)
        for index in 0..<count {
            var entry = try DiaryEntry(food: food, amount: 1, unit: .serving,
                                       meal: Meal.allCases[index % Meal.allCases.count],
                                       day: days[index % days.count], language: .en)
            entry.id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", index + 1))!
            entry.created = "2026-10-21T00:00:00Z"
            snapshot.entries.append(entry)
        }
        // Warm-up and reference bytes are outside the recorded samples. All
        // samples must retain byte-identical JSON and strict invalid-day checks.
        let expected = try Backup.encode(snapshot)
        var wall: [Double] = [], cpu: [Double] = [], peak: [Int64] = []
        for _ in 0..<3 {
            let resources = usage(), start = ProcessInfo.processInfo.systemUptime
            let encoded = try Backup.encode(snapshot)
            let finish = ProcessInfo.processInfo.systemUptime, after = usage()
            guard encoded == expected else { fatalError("Encoding changed within the benchmark") }
            wall.append(finish - start)
            cpu.append(after.cpu - resources.cpu)
            peak.append(after.peak)
        }
        var invalid = snapshot
        invalid.entries[invalid.entries.count - 1].day = "2026-02-30"
        do { _ = try Backup.encode(invalid); fatalError("Invalid date was accepted") } catch {}
        invalid.entries[invalid.entries.count - 1].day = "not-a-date"
        do { _ = try Backup.encode(invalid); fatalError("Invalid date was accepted") } catch {}
        let output: [String: Any] = [
            "schema": 1, "status": "measured", "scenario": "Backup.encode valid 5000-entry seven-day snapshot",
            "fixture": "core-encode-v1-20261021-5000-7", "entries": count, "unique_days": days.count,
            "iterations": 3, "warmup_iterations": 1, "compiler_optimization": "-O",
            "encoded_bytes": expected.count,
            "encoded_sha256": SHA256.hash(data: expected).map { String(format: "%02x", $0) }.joined(),
            "wall_seconds": wall, "process_cpu_seconds": cpu, "process_peak_resident_bytes": peak,
            "invalid_day_checks_passed": 2,
            "limitations": ["macOS core-serialization microbenchmark, not iOS application launch or FPS",
                            "ru_maxrss is process lifetime high-water memory, not per-sample allocation or app memory",
                            "fixture construction, warm-up, equality and invalid-date checks are outside timed spans"]
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}
'''


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def export_result_bundle(bundle: Path, output: Path, report: dict) -> dict:
    """Retain available raw evidence without masking a prior test failure."""
    exported = {}
    for kind in ('summary', 'metrics'):
        label = 'xcresult-' + kind
        try:
            value = json.loads(execute(['xcrun', 'xcresulttool', 'get', 'test-results', kind,
                                        '--path', str(bundle)], output, label))
            write_json(output / (label + '.json'), value)
            exported[kind] = value
        except (BuildError, OSError, ValueError) as error:
            report.setdefault('result_export_errors', {})[kind] = str(error)
    report['exported_result_files'] = ['xcresult-' + kind + '.json' for kind in exported]
    return exported


def execute(args: list[str], output: Path, label: str, timeout: int = 120,
            allow_failure: bool = False) -> str:
    """No shell interpolation, secret arguments, global service restarts or deletes."""
    print('Luqma performance ' + label + ': ' + shlex.join(args), flush=True)
    path = output / (label + '.log')
    try:
        completed = subprocess.run(args, cwd=ROOT, env=public_environment(),
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   timeout=timeout, check=False)
    except subprocess.TimeoutExpired as error:
        path.write_bytes(error.stdout or b'')
        raise BuildError(f'{label} exceeded {timeout}s; evidence retained in {path.name}.') from error
    path.write_bytes(completed.stdout)
    result = completed.stdout.decode('utf-8', errors='replace')
    if completed.returncode and not allow_failure:
        print('\n'.join(result.splitlines()[-45:]), file=sys.stderr)
        raise BuildError(f'{label} failed ({completed.returncode}); see {path.name}.')
    return result


def source_identity() -> dict:
    command = ['git', '-C', str(ROOT), 'rev-parse', 'HEAD']
    revision = subprocess.run(command, capture_output=True, text=True, check=True).stdout.strip()
    status = subprocess.run(['git', '-C', str(ROOT), 'status', '--porcelain'],
                            capture_output=True, text=True, check=True).stdout.splitlines()
    files = []
    for directory in ('Luqma', 'Luqma.xcodeproj'):
        files.extend(path for path in (ROOT / directory).rglob('*') if path.is_file())
    files.extend(ROOT / name for name in ('Package.swift', 'TestsUI/LuqmaPerformanceTests.swift',
                                         'Scripts/performance_probe.py'))
    records = [(path.relative_to(ROOT).as_posix(), hashlib.sha256(path.read_bytes()).hexdigest())
               for path in sorted(set(files))]
    digest = hashlib.sha256(json.dumps(records, separators=(',', ':')).encode()).hexdigest()
    fixture = ROOT / 'Luqma/Services/PerformanceFixtures.swift'
    return dict(revision=revision, working_tree_status=status, files_sha256=records,
                application_and_harness_sha256=digest,
                fixture_source_sha256=hashlib.sha256(fixture.read_bytes()).hexdigest() if fixture.is_file() else None,
                probe_script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                test_harness_sha256=hashlib.sha256((ROOT / 'TestsUI/LuqmaPerformanceTests.swift').read_bytes()).hexdigest())


def samples_from(value: object) -> list[float] | None:
    """Accept only actual explicit sample arrays; never reverse-engineer averages."""
    if not isinstance(value, list) or not value:
        return None
    result = []
    for item in value:
        if isinstance(item, dict):
            keys = [key for key in ('value', 'measurementValue', 'doubleValue') if key in item]
            if len(keys) != 1:
                return None
            item = item[keys[0]]
        if isinstance(item, bool) or not isinstance(item, (int, float)) or not math.isfinite(item):
            return None
        result.append(float(item))
    return result


def normalize_metrics(raw: object) -> list[dict]:
    """Preserve raw JSON; summarize only unambiguous named metric/sample records.

    xcresulttool is versioned. An unrecognized schema remains raw evidence and
    fails the normalized-data gate instead of becoming invented measurements.
    """
    found = []

    def walk(item: object, context: str = '', path: str = '$') -> None:
        if isinstance(item, list):
            for index, child in enumerate(item):
                walk(child, context, f'{path}[{index}]')
            return
        if not isinstance(item, dict):
            return
        for key in ('testIdentifier', 'testIdentifierURL', 'testName'):
            if isinstance(item.get(key), str):
                context = item[key]
                break
        title = next((item[key] for key in ('displayName', 'metricName', 'identifier', 'name')
                      if isinstance(item.get(key), str)), None)
        unit = next((item[key] for key in ('unitOfMeasurement', 'unit', 'units')
                     if isinstance(item.get(key), str)), None)
        if title and unit:
            for key in ('measurements', 'values', 'samples', 'iterationValues'):
                values = samples_from(item.get(key))
                if values is not None:
                    found.append(dict(test=context, metric=title,
                                      identifier=item.get('identifier'), unit=unit,
                                      sample_count=len(values), samples=values,
                                      mean=statistics.fmean(values), median=statistics.median(values),
                                      population_stddev=statistics.pstdev(values),
                                      minimum=min(values), maximum=max(values), raw_json_path=path))
                    break
        for key, child in item.items():
            if isinstance(child, (dict, list)):
                walk(child, context, path + '.' + key)

    walk(raw)
    return found


def compare_reports(before: dict, after: dict) -> dict:
    """A before/after table is permitted only for comparable actual metrics."""
    if before.get('status') != 'measured' or after.get('status') != 'measured':
        raise BuildError('Both reports must contain successfully measured performance data.')
    for key in ('fixture_identity', 'configuration', 'optimization', 'active_compilation_conditions',
                'device_type', 'runtime_identifier', 'runtime_version', 'xcode_version', 'swift_version',
                'host_architecture', 'host_timezone', 'host_local_day', 'test_harness_sha256',
                'fixture_source_sha256', 'required_tests'):
        if before.get(key) != after.get(key):
            raise BuildError('Before/after configurations differ: ' + key)
    left = {(row['test'], row['metric'], row['unit']): row for row in before['normalized_metrics']}
    right = {(row['test'], row['metric'], row['unit']): row for row in after['normalized_metrics']}
    if len(left) != len(before['normalized_metrics']) or len(right) != len(after['normalized_metrics']):
        raise BuildError('Duplicate metric identities require manual review; comparison was not synthesized.')
    rows = []
    for key in sorted(left.keys() | right.keys()):
        previous, current = left.get(key), right.get(key)
        if previous is None or current is None:
            rows.append(dict(test=key[0], metric=key[1], unit=key[2], status='Not Measured on both revisions'))
            continue
        if previous['sample_count'] != current['sample_count']:
            raise BuildError('Metric iteration counts differ: ' + str(key))
        start, finish = previous['median'], current['median']
        # This is explicitly a lower-is-better numeric change, not a blanket
        # improvement: cycles/instructions/peak/growth metrics retain own units.
        percentage = (start - finish) / start * 100 if start > 0 else None
        rows.append(dict(test=key[0], metric=key[1], unit=key[2],
                         before_median=start, after_median=finish,
                         lower_is_better_change_percent=percentage,
                         sample_count=previous['sample_count'],
                         before_stddev=previous['population_stddev'], after_stddev=current['population_stddev']))
    return dict(before_revision=before['source']['revision'], after_revision=after['source']['revision'],
                before_host=before.get('host_name'), after_host=after.get('host_name'),
                same_host=before.get('host_name') == after.get('host_name'), rows=rows,
                limitations=LIMITATIONS,
                observed_fps='Not Measured', frame_time_distribution='Not Measured',
                physical_promotion='Not Measured', energy='Not Measured')


def run_core_benchmark(output: Path) -> dict:
    """Compile the actual current Core with a temporary public macOS harness.

    No source edits, Package.swift changes, extra test dependency or alternate
    nutritional implementation. The exact source revision/hashes stay in the
    parent report. macOS microbenchmarks must never be labeled iOS UI metrics.
    """
    harness = output / 'core-benchmark.swift'
    harness.write_text(CORE_BENCHMARK, encoding='utf-8')
    binary = output / 'luqma-core-benchmark'
    sources = sorted(str(path) for path in (ROOT / 'Luqma/Core').glob('*.swift'))
    execute(['xcrun', 'swiftc', '-O', '-parse-as-library', *sources, str(harness), '-o', str(binary)],
            output, 'core-benchmark-compile', 600)
    raw = json.loads(execute([str(binary)], output, 'core-benchmark-run', 600))
    if (raw.get('status') != 'measured' or raw.get('entries') != 5000
            or raw.get('iterations') != 3 or raw.get('invalid_day_checks_passed') != 2):
        raise BuildError('Core benchmark did not complete its actual data and validation checks.')
    for key in ('wall_seconds', 'process_cpu_seconds', 'process_peak_resident_bytes'):
        values = samples_from(raw.get(key))
        if values is None or len(values) != 3 or any(value < 0 for value in values):
            raise BuildError('Core benchmark contains missing or invalid raw measurements.')
    write_json(output / 'core-benchmark.json', raw)
    return raw


def run_probe(args: argparse.Namespace) -> None:
    output = args.output.resolve()
    if output.exists():
        raise BuildError('Choose a new performance output directory; existing evidence is preserved.')
    output.mkdir(parents=True)
    started = time.monotonic()
    device = None
    report = dict(schema=1, status='running', label=args.label,
                  started_at=datetime.now(timezone.utc).isoformat(),
                  fixture_identity=FIXTURE_IDENTITY, configuration='Release', optimization='-O',
                  active_compilation_conditions='DEBUG (isolated fixture hook only)',
                  required_tests=list(TESTS), requested_iterations=dict(default=3, process_launch=5),
                  host_architecture=platform.machine(), host_name=platform.node(),
                  host_timezone=str(datetime.now().astimezone().tzinfo),
                  host_local_day=datetime.now().astimezone().date().isoformat(),
                  host_platform=platform.platform(), developer_dir=os.environ.get('DEVELOPER_DIR'),
                  device_type=args.device_type, physical_device_verified=False,
                  promotion_120hz_verified=False, observed_fps='Not Measured',
                  frame_time_distribution='Not Measured', battery_impact='Not Measured',
                  existing_device_data_modified=False, limitations=LIMITATIONS)
    try:
        require_mac(26)
        identity = source_identity()
        report['source'] = identity
        report['test_harness_sha256'] = identity['test_harness_sha256']
        report['fixture_source_sha256'] = identity['fixture_source_sha256']
        if args.expected_revision and identity['revision'] != args.expected_revision:
            raise BuildError('The checked-out source revision does not match --expected-revision.')
        report['xcode_version'] = execute(['xcodebuild', '-version'], output, 'xcode-version').strip()
        report['swift_version'] = execute(['swift', '--version'], output, 'swift-version').strip()
        report['core_benchmark'] = run_core_benchmark(output)
        if args.core_only:
            report['status'] = 'core_only_measured'
            report['ui_performance'] = 'Not Measured'
            return
        if not identity['fixture_source_sha256']:
            raise BuildError('The isolated production-file fixture implementation is missing; do not measure an empty application.')
        project = (ROOT / 'Luqma.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
        if 'LuqmaPerformanceTests.swift' not in project:
            raise BuildError('Add the performance Swift file to the actual UI-test target before running this probe.')
        execute(['xcrun', 'xctrace', 'list', 'templates'], output, 'available-instruments', allow_failure=True)
        inventory = json.loads(execute(['xcrun', 'simctl', 'list', '--json'], output, 'simulator-inventory'))
        runtime = select_runtime(inventory)
        report.update(runtime_identifier=runtime['identifier'], runtime_version=runtime['version'])
        device = execute(['xcrun', 'simctl', 'create', 'Luqma Performance ' + uuid.uuid4().hex[:8],
                          args.device_type, runtime['identifier']], output, 'create-simulator').strip()
        if not re.fullmatch(r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', device):
            device = None
            raise BuildError('Simulator creation returned an invalid identifier.')
        report['simulator_udid'] = device
        report['fresh_simulator'] = True
        report['preparation'] = prepare_created_simulator(
            device, lambda command, label, timeout: execute(command, output, label, timeout))
        packages = args.packages.resolve()
        apply_vision_compat(packages)
        # Keep multi-gigabyte build intermediates out of the retained metrics
        # artifact. They are neither test evidence nor app-memory measurements.
        derived = args.derived.resolve() if args.derived else output.parent / (output.name + '-derived')
        bundle = output / 'performance.xcresult'
        report['result_bundle'] = str(bundle)
        selection = ['-only-testing:LuqmaUITests/LuqmaPerformanceTests/' + name for name in TESTS]
        build = ['xcodebuild', '-project', 'Luqma.xcodeproj', '-scheme', 'Luqma',
                 '-clonedSourcePackagesDirPath', str(packages), '-disableAutomaticPackageResolution',
                 '-destination', 'id=' + device, '-configuration', 'Release',
                 '-derivedDataPath', str(derived), '-resultBundlePath', str(bundle),
                 '-parallel-testing-enabled', 'NO', '-enableCodeCoverage', 'NO',
                 *selection, 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGNING_ALLOWED=NO',
                 'SWIFT_OPTIMIZATION_LEVEL=-O', 'SWIFT_COMPILATION_MODE=wholemodule',
                 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG', 'test']
        report['xcodebuild_arguments'] = build
        try:
            log = execute(build, output, 'native-performance', args.timeout)
        finally:
            # Even a nonzero xcodebuild result can contain valid diagnostic
            # metrics/schema data. Export it without swallowing that failure.
            exported = export_result_bundle(bundle, output, report)
        passed = [name for name in TESTS if re.search(r"Test Case '.*" + re.escape(name) + r".*' passed", log)]
        report['passed_tests'] = passed
        if len(passed) != len(TESTS):
            raise BuildError('The actual performance run did not pass every required scenario.')
        if 'summary' not in exported or 'metrics' not in exported:
            raise BuildError('Required result-bundle JSON could not be exported; see retained xcresult logs.')
        raw = exported['metrics']
        report['normalized_metrics'] = normalize_metrics(raw)
        if not report['normalized_metrics']:
            raise BuildError('Raw metrics were retained, but this xcresult metric schema needs explicit review; no numbers were invented.')
        missing = [name for name in TESTS if not any(name in row['test'] for row in report['normalized_metrics'])]
        if missing:
            raise BuildError('Raw metrics need explicit scenario attribution for: ' + ', '.join(missing))
        apply_vision_compat(packages, verify_only=True)
        report['status'] = 'measured'
        if args.compare:
            previous = json.loads(args.compare.read_text(encoding='utf-8'))
            comparison = compare_reports(previous, report)
            write_json(output / 'before-after.json', comparison)
            report['comparison'] = 'before-after.json'
    except BaseException as error:
        report['status'] = 'unavailable' if platform.system() != 'Darwin' else 'failed'
        report['error'] = str(error)
        raise
    finally:
        if device:
            for operation in ('shutdown', 'delete'):
                try:
                    execute(['xcrun', 'simctl', operation, device], output, 'cleanup-' + operation,
                            90, allow_failure=True)
                except (BuildError, OSError) as error:
                    report.setdefault('cleanup_warnings', []).append(str(error))
        report['elapsed_seconds'] = round(time.monotonic() - started, 3)
        report['completed_at'] = datetime.now(timezone.utc).isoformat()
        write_json(output / 'performance-report.json', report)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--label', choices=('baseline', 'optimized'), required=True)
    parser.add_argument('--expected-revision')
    parser.add_argument('--packages', type=Path, default=Path('BuildOutput/Packages'))
    parser.add_argument('--derived', type=Path)
    parser.add_argument('--device-type', default=DEVICE_TYPE)
    parser.add_argument('--timeout', type=int, default=2400)
    parser.add_argument('--compare', type=Path, help='Successful actual baseline performance-report.json')
    parser.add_argument('--core-only', action='store_true', help='Run only the actual macOS Core encode microbenchmark; no Simulator or UI measurement')
    args = parser.parse_args()
    if not 300 <= args.timeout <= 5400:
        parser.error('--timeout must be between 300 and 5400 seconds.')
    if args.expected_revision and not re.fullmatch(r'[0-9a-f]{40}', args.expected_revision):
        parser.error('--expected-revision must be an exact lowercase 40-character commit SHA.')
    if not re.fullmatch(r'com\.apple\.CoreSimulator\.SimDeviceType\.[A-Za-z0-9-]+', args.device_type):
        parser.error('--device-type must be an Apple Simulator device type identifier.')
    if args.core_only and args.compare:
        parser.error('--compare is for actual UI metrics; core-only JSON must be compared separately with matching fixture bytes.')
    try:
        run_probe(args)
    except (BuildError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
