#!/usr/bin/env python3

name = "Dave"
count = 1
# def greeting(name: str) -> None:
# 	color = "blue"
# 	print(color)
# 	print(name)

# greeting(name)
# greeting("john")

def another_func(newstring: str) -> None:
	color = "blue"
	global count 
	count += 1
	print(count)

	def greeting(name: str) -> None:
		print(color)
		print(name)

	greeting("mike")
	print(newstring)


print(count)
print("")
another_func("paul")

