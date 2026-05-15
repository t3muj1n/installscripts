#!/usr/bin/env python3

def hello_world():
	print("Hello World!\n")

hello_world()


def sum (num1=0, num2=0):
	if (type(num1) is not int or type(num2) is not int):
		return
	return num1 + num2

total = sum()
total = sum(2, 3)

print(total)


def multiple_items(*args):
	print(args)
	print(type(args))

multiple_items("dave", "john", "sara")



def mult_named_items(**kwargs):
	print(kwargs)
	print(type(kwargs))

mult_named_items(first ="dave", last = "gray")

# recursion

def add_one(num):
	if (num >= 9):
		return num + 1

	total = num + 1
	print(total)
	return add_one(total)

mynewtotal = add_one(0)
print("")
add_one(0)
print("")
print(mynewtotal)

####################
value = True
while value:
	print(value)
	value = False

value = "y"
while value:
	print(value)
	value = False

count = 0
while value:
	if (count == 5):
		break
	else:
		value = False
		continue

print(value, count)
