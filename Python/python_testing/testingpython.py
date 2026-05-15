#!/usr/bin/env python3

from typing import Union

def some_calculations(x: Union[int, float], y: Union[int, float]) -> Union[int, float]:
		return (x +y) ** 2


numbers = list(range(100))

squared = []
# not this way
for number in numbers:
	if number % 5 == 0:
		squared.append(number ** 2)

# this is the way
squared = [number ** 2 for number in numbers if number %5 == 0]
print(squared)

# not this way
filtered_list = []
for x in numbers:
	if x % 5 == 0 and x % 3 == 0:
		filtered_list.append(x)


# this is the way
print(filtered_list)
filtered_list = list(filter(lambda x: x % 5 == 0 and x % 3 == 0, numbers))
print(filtered_list)