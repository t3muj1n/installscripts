#!/usr/bin/env python3

import sys
import random
from enum import Enum

def play_rps():


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

	if playerchoice not in ["1","2","3"]:
		print("invalid choice must be 1, 2, or 3.")
		play_rps()

	player = int(playerchoice)

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

	print("play again?\n")
	while True:
		playagain = input("y for yes\nn for no\nq for quit\n")
		if playagain.lower() not in ["y", "n", "q"]:
			continue
		else:
			break

	if playagain.lower() == "y":
		play_rps()
	else: 
		print("thanks for playing!")
		sys.exit("bye!\n")
		#break


play_rps()
