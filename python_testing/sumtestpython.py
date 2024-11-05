#!/usr/bin/env python3

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
