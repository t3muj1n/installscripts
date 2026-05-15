#!/usr/bin/env python3

number: int = 10	# interger
decimal: float = 2.5	# floating point number
text: str = 'hello world!'	# string
active: bool = False 	# boolean
name: list = ['bob', 'anna', 'luifi']	# list
coordinates: tuple = (1.5, 2.5, 3.5)	# tuple
unique: set = {1, 4, 2, 9}				# set 
data: dict = {'name': 'bob', 'age': 20} # dictionary

# use capslock to indicate constant

#VERSION: Final[str] = '1.0.12'		# the Final indicates its const
#VERSION = '1.0.13'					# it can still be changed but
									# there is a warning.

print("my number is", number, "and my text is", text, sep=",")
print("hello world.", end=" | ")
print("this is a test!", end="\n")

rng = range(10)
print(list(rng))
rng = range(2,10)
print(list(rng))
rng = range(2, 10, 2)
print(list(rng))


#output the lengths
strings = ["my","world","apple","pear", "orange"]
lengths = map(len, strings)
print(list(lengths))
#use a lambda to modify the strings.
lengths = map(lambda x:  x + "s", strings)
print(list(lengths))

#this section is the same as above
def add_s(string):
	return string + "s"

lengths = map(add_s, strings)
print(list(lengths))

#filter
def longer_than_4(string):
	return len(string) > 4


strings = ["my","world","apple","pear", "orange"]
filtered = filter(longer_than_4, strings)
print(list(filtered))

#################3


numbers = {1,4,5,23,2,10,15}
print(sum(numbers))
print(sum(numbers, start=10))

sorted_nums = sorted(numbers)
print(sorted_nums)
sorted_nums = sorted(numbers, reverse=True)
print(sorted_nums)


######

people = [
	{"name": "alice", "age": 30},
	{"name": "bob", "age": 25},
	{"name": "charlie", "age": 35},
	{"name": "david", "age": 20},
]

sorted_people = sorted(people, key=lambda person: person["age"])
print(sorted_people)
sorted_people = sorted(people, key=lambda person: person["age"], reverse=True)
print(sorted_people)

#########
tasks = ["write report", "Attend meeting","Review code","Submit timesheet"]

for index in range(len(tasks)):
 	task = tasks[index]
 	print(f"{index +1}. {task}")

print()
for index, task in enumerate(tasks):
 	print(f"{index + 1}. {task}")

print()
print(list(enumerate(tasks)))

print("##############")
print()

names = ["Alice", "Charlie", "Bob", "David"]
ages = [30, 35, 25, 20]

for index in range(min(len(names), len(ages))):
	name = names[index]
	age = ages[index]
	print(f"{name} is {age} years old")

print()
combined = list(zip(names, ages))
print(combined)
for name, age in combined:
	print(f"{name} is {age} years old")

#####################
from datetime import datetime
print("###########")
name = "alice"
age = 30

old_format = "hello, name: {} and age: {} years".format(name, age)

f_string = f"hell, name: {name} and age: {age} years"
print("using fstring: ", f_string)

price = 1234.5678
print(f"the prise: ${price:.2f}")

large_number = 100000000
print(f"{large_number:,}")

now = datetime.now()
print(f"todays date: {now:%Y %m %d %H %M %S %s}")
print(now)


#######################
print("##############")
print()

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
show_date()
######################

file = open("test.txt", "w")			# create or overwrite a file
file.write("hello world\nthis is a second line\n")
file.close()
#below is a better way


#within the context manager. once we fall off the end it close the file handler
with open("test.txt", "w") as file:
	file.write("hellow world\nthis is a second line\n")

with open("test.txt", "r") as file:
	text = file.read()
	print(text)

with open("test.txt", "a") as file:
	file.write("new newline\n")

with open("test.txt", "r") as file:
	text = file.read()
	print(text)
	
print()
#########################
print("###########################")
print()
from datetime import datetime
name = "alice"
age = 30

old_format = "hello, name: {} and age: {} years".format(name, age)

f_string = f"hell, name: {name} and age: {age} years"
print("using fstring: ", f_string)

price = 1234.5678
print(f"the prise: ${price:.2f}")

large_number = 100000000
print(f"{large_number:,}")

now = datetime.now()
print(f"todays date: {now:%Y %m %d %H %M %S %s}")
print(now)

###########
print("#" * 20)
title = "menu".upper()
print(title.center(20, "+"))
print("Coffee".ljust(16, ".") + "$1".rjust(4))
print("Muffin".ljust(16, ".") + "$2".rjust(4))
print("cheesecake".ljust(16, ".") + "$4".rjust(4))
print("#" * 20)

print("")

print(title[1])
print(title[-1])
print(title[1:-1])
print(title[1:])

#some methods return boolean data

print(title.startswith("M"))
print(title.startswith("m"))
print(title.endswith("U"))
print(title.endswith("u"))

myval = True
x = bool(False)
print(type(x))
print(isinstance(myval, bool))

##
#numeric data types
price = 100 
best_price = int(80)
print(type(price))
print(type(best_price))

#complex type

comp_value = 5+3j
print(type(comp_value))
print(comp_value.real)
print(comp_value.imag)

print(abs(best_price))
print(abs(best_price * -1))
print(round(best_price))
print(round(best_price, 1))
print()
######################
import math
print(math.sqrt(64))
print(math.ceil(best_price))
print(math.floor(best_price))
print(math.pi)


#########
users = ['Dave', 'John', 'Sara']
data = ['Dave', 42, True]

emptylist = []

print("Dave" in users)
print("dave" in data)
print(users)
print(users[0])
print([-2])
print(users.index('Sara'))
print(users[0:2])
print(users[1:])
print(users[-3:-1])
print(len(data))
users.append('Elsa')
print(users)

users += ['Jason']
print(users)
users.extend(['Robert', 'James'])
users.insert(0, 'Bob')
print(users)
users[2:2] = ['Eddie', 'Alex']

users.remove('Bob')
print(users)
users.pop(1)
print(users)
users.sort()
print(users)
