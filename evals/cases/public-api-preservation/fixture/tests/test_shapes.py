import math
import unittest

import geometry


class ShapesTest(unittest.TestCase):
    def test_circle(self):
        self.assertAlmostEqual(geometry.area_of_circle(1), math.pi)
