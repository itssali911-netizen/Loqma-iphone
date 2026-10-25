import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Scripts'))
import ui_interactions
from build_ios import BuildError


class IndependentScenarioEvidenceTests(unittest.TestCase):
    def test_failed_assessment_does_not_hide_other_fresh_permission_scenarios(self):
        actual=[]
        def scenario(output,packages,derived,runtime,methods,report,build):
            actual.append((report['name'],methods))
            report['fresh_simulator']=True
            report['simulator']={'udid':report['name']}
            if report['name']=='fitness-assessment':
                report['status']='failed'
                raise BuildError('Actual assessment assertion failed')
            report.update(status='passed',passed_cases=list(methods))
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)/'evidence'
            with patch.object(ui_interactions,'require_mac'), \
                    patch.object(ui_interactions,'command',return_value='{}'), \
                    patch.object(ui_interactions,'select_runtime',return_value={}), \
                    patch.object(ui_interactions,'apply_vision_compat'), \
                    patch.object(ui_interactions,'run_scenario',side_effect=scenario), \
                    patch.object(ui_interactions,'validate_app') as validate:
                with self.assertRaisesRegex(BuildError,'fitness-assessment: Actual assessment assertion failed'):
                    ui_interactions.run_tests(output,Path(directory)/'packages',Path(directory)/'derived')
                validate.assert_not_called()
            result=json.loads((output/'interaction-report.json').read_text('utf-8'))
        self.assertEqual([name for name,_ in actual],['fitness-assessment','permission-allowed','permission-denied'])
        self.assertEqual(set.union(*(set(methods) for _,methods in actual)),set(ui_interactions.TESTS))
        self.assertEqual(result['status'],'failed')
        self.assertEqual([s['status'] for s in result['scenarios']],['failed','passed','passed'])
        self.assertEqual(result['scenario_execution_order'],[name for name,_ in actual])
        self.assertNotIn('passed_cases',result)

    def test_cancellation_does_not_start_another_scenario(self):
        actual=[]
        def cancelled(output,packages,derived,runtime,methods,report,build):
            actual.append(report['name'])
            raise KeyboardInterrupt()
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)/'evidence'
            with patch.object(ui_interactions,'require_mac'), \
                    patch.object(ui_interactions,'command',return_value='{}'), \
                    patch.object(ui_interactions,'select_runtime',return_value={}), \
                    patch.object(ui_interactions,'apply_vision_compat'), \
                    patch.object(ui_interactions,'run_scenario',side_effect=cancelled):
                with self.assertRaises(KeyboardInterrupt):
                    ui_interactions.run_tests(output,Path(directory)/'packages',Path(directory)/'derived')
            result=json.loads((output/'interaction-report.json').read_text('utf-8'))
        self.assertEqual(actual,['fitness-assessment'])
        self.assertEqual(result['status'],'failed')
        self.assertEqual(result['scenario_execution_order'],['fitness-assessment'])


if __name__=='__main__':
    unittest.main()
