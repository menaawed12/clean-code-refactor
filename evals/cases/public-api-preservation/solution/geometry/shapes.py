import math


def area_of_circle(radius):
    return math.pi * radius * radius


def area_of_square(side):
    return side * side


def perimeter_of_square(side):
    return 4 * side


# Deprecated camelCase names, kept so existing importers keep working.
areaOfSquare = area_of_square
perimeterOfSquare = perimeter_of_square
