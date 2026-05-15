#!/usr/bin/env python3 


# 1. keep the name short and concise
# 2. specify the return type
# 3. make it as simple and reusable as possible
# 4. document all your functions
# 5. handle errors 

# try:
#     from collections.abc import Iterable
# except ImportError:
#     from collections import Iterable

from collections.abc import Iterable

def get_total_discount(prices: Iterable[float], percent:float) -> float:
	# validate input

	if not (0 <= 1):
		raise ValueError(f'Invalid discount rate: {percent}. Must be between 0 and 1 inclusive.')

	if not all(isinstance(price, (int, float)) and price >= 0 for price in prices):
		raise ValueError('All prices must be non-negative numbers')

# Breakdown:
# all( ... ):
# This function checks if every element in an iterable (like a list) evaluates to True within the provided condition. If even one element is False, the entire all function returns False.
# isinstance(price, (int, float)):
# This part checks if the current element (price) is either an integer (int) or a floating-point number (float).
# price >= 0:
# This checks if the current element (price) is greater than or equal to zero.
# for price in prices:
# This loop iterates through each element in the list prices, assigning each element to the variable price for checking within the condition.

	total: float = sum(prices)
	return total * (1 - percent)

def main() -> None:
	output: float = get_total_discount([100.0, 50.0, 25.0], 0.2)
	print(output)

if __name__ == '__main__':
		main()

