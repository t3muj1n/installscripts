#! /usr/bin/env python3
person = "Dave"
coins = 3

print(person + " has " + str(coins) + "coins left. msg1 \n")

message = "%s has %s coins left. msg2 \n" % (person, coins)
print(message)

message = "{} has {} coins left. msg3 \n" .format(person, coins)
print(message)

message = "{0} has {1} coins left. msg4 \n" .format(person, coins)
print(message)

message = "{person} has {coins} coins left. msg5 \n" .format(coins=coins, person=person)
print(message)

player = { 'person': 'Dave', 'coins': 3}

message = "{person} has {coins} coins left. msg6 \n" .format(**player)
print(message)
print(type(player))


################
#fstrings !

message = f"{person} has {coins} left.\n"
print(message)

message = f"{person} has {2 * 5} left.\n"
print(message)

message = f"{person.lower()} has {coins} left.\n"
print(message)

player = { 'person': 'Dave', 'coins': 3}
message = f"{player['person'].lower()} has {2 *5} coins left\n"
print(message)

num = 10
print(f"2.25 times {num} is {2.25 * num:.2f}\n")


for num in range(1,11):
	print(f"2.25 times {num} is {2.25 * num:.2f}\n")

for num in range(1,11):
	print(f"{num} divided by 4.52 ia {num / 4.52:.2%}")
