#!/usr/bin/env python3
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


###################3
#Tuples

mylist = list([1, "Neil", True])
print(mylist)

mytuple= tuple(('Dave', 42, True))
anothertuple = (1, 4, 2, 6, 8, 2, 2)
print(type(mytuple))
print(type(anothertuple))
print(mytuple)
#tuples cant be changed but they vcan be copies to a new tuple or list
newlist = list(mytuple)
newlist.append('Neil')
newtuple = tuple(newlist)
print(newtuple)
#unpacking a list
#the * makes it a list of values 
(one, *two, three, ) = anothertuple
print(one)
print(two)
print(three)
print(anothertuple.count(2))