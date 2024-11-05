#!/usr/bin/env python3

import sys
import random
from enum import Enum

class RPS(Enum):
	ROCK = 1
	PAPER = 2
	CISSORS = 3

print(RPS(2))
print(RPS.ROCK)
print(RPS['ROCK'])
print(RPS.ROCK.value)

print("")
playerchoice = input("enter 1 for rock\n2 for paper\n3 for cissors\n")

player = int(playerchoice)
if player < 1 or player > 3:
	sys.exit("please enter 1, 2, or 3")

computerchoice = random.choice("123")
computer = int(computerchoice)
print("")
print("your choice: " + str(RPS(player)).replace('RPS.','') + ".")
print("pythons choice: " + str(RPS(computer)).replace('RPS.','') + ".")
print
#emojis can be embedded in the print statements. interesting
if player == 1 and computer == 3:
	print("you win!")
elif  player == 2 and computer == 1:
	print("you win!")
elif player == 3 and computer == 2:
	print("you win!")
elif player == computer:
	print("tie game!")
else:
	print("python wins")


