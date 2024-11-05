#!/usr/bin/env python3

# value = 1
# while value < 10:
# 	print(value)
# 	if value == 5:
# 		break
# 	value += 1

# print(value)

# value = 1
# while value < 10:
# 	value += 1
# 	if value == 5:
# 		continue
# 	print(value)
# else:
# 	print("value is now equal to" + str(value))


names = ["dave", "Sara", "John"]
# for x in names:
# 	if x == "Sara":
# 		break
# 	print(x)
for x in names:
	if x == "Sara":
		continue
	print(x)

# for i in "Mississippi":
# 	print(i)


for x in range(4):
	print(x)

print("")
for x in range(2, 4):
	print(x)

for x in range(0, 100, 5):
	print(x)
else:
	print("finished!")


names = ["Dave", "Sara", "John"]
actions = ["codes", "eats", "sleeps"]

for name in names:
	for action in actions:
		print(name + " " + action + ".")



for action in actions:
	for name in names:
		print(name + " " + action + ".")