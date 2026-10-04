import unittest


class PublicApiTest(unittest.TestCase):
    def test_existing_importers_keep_working(self):
        from geometry import area_of_circle, areaOfSquare, perimeterOfSquare
        from geometry.shapes import areaOfSquare as direct_area, perimeterOfSquare as direct_perimeter

        self.assertEqual(areaOfSquare(3), 9)
        self.assertEqual(perimeterOfSquare(3), 12)
        self.assertEqual(direct_area(2), 4)
        self.assertEqual(direct_perimeter(2), 8)
        self.assertGreater(area_of_circle(1), 3.14)
