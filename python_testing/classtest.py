#!/usr/bin/env python3

class Car:
	def __init__(self, color: str, horsepower: int) -> None:
		self.color = color
		self.horsepower = horsepower




volvo: Car = Car('red', 200)
print(volvo.color)
print(volvo.horsepower)


bmw: Car = Car('white', 250)

print(bmw.color)
print(bmw.horsepower)


