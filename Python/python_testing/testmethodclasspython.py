#!/usr/bin/env python3
from typing import TypeVar

Self = TypeVar('Self')

#self refers to the instance oc the class like volvo
class Car:
	def __init__(self, brand: str, horsepower: int) -> None:
		self.brand = brand
		self.horsepower = horsepower

	def drive(self) -> None:
		print(f'{self.brand} is driving!')

	def get_info(self, var: int) -> None:
		print(var)
		print(f'{self.brand} with {self.horsepower} horsepower!')
# dunder methods.
	def __str__(self) -> str:
		return f'{self.brand}, {self.horsepower}hp'

	def __add__(self, other: Self) -> str:
		return f'{self.brand}, & {other.brand}'



volvo: Car = Car('volvo', 200)
volvo.get_info(volvo.horsepower)
volvo.drive()

bmw: Car = Car('BMW', 240)
bmw.get_info(10)
bmw.drive()


print('##################')

print(volvo)
print()
print(volvo + bmw)
