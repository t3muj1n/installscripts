#!/usr/bin/env python3

from datetime import datetime

def show_date() -> None: 
	print('this is the current date and time:')
	print(datetime.now())

show_date()

def greet(name: str) -> None:
	print(f'Hello, {name}!')

greet('bob')
greet('luigi')


def add(a: float, b: float) -> float:
	return a + b

print(add(1.23, 2.23))
