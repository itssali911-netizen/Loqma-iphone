import unittest
from prepare import safe_member

class ArchiveBoundaryTests(unittest.TestCase):
    def test_source_file_is_relative_to_expected_crate(self):
        self.assertEqual(safe_member('isideload-0.5.0/src/lib.rs'), ('src', 'lib.rs'))

    def test_rejects_traversal_absolute_paths_and_windows_drive_paths(self):
        for value in ('/etc/passwd', 'isideload-0.5.0/../out', 'C:/outside',
                      'isideload-0.5.0/C:/outside', 'isideload-0.5.0/src\\..\\outside'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                safe_member(value)

    def test_rejects_wrong_archive_root(self):
        with self.assertRaises(ValueError):
            safe_member('another-crate/src/lib.rs')

if __name__ == '__main__':
    unittest.main()
