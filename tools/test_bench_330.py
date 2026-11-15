import unittest
import update_bench_330 as bench


class SourceValidation(unittest.TestCase):
    def test_rejects_unreviewed_source(self):
        with self.assertRaisesRegex(ValueError, "does not match"):
            bench.build(b"[]", b"{}")


if __name__ == "__main__":
    unittest.main()
