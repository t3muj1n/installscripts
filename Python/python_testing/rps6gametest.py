#!/usr/bin/env python3

import sys
import random
from enum import Enum

def rps():
	game_count = 0
	player_wins = 0
	python_wins = 0

	def play_rps():
		nonlocal player_wins
		nonlocal python_wins


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
		print(f"your choice: {str(RPS(player)).replace('RPS.','')}.")
		print(f"pythons choice: {str(RPS(computer)).replace('RPS.','')}.\n")
		#emojis can be embedded in the print statements. interesting
		def decide_winner( player, computer):
			nonlocal player_wins
			nonlocal python_wins

			if player == 1 and computer == 3:
				player_wins += 1
				return "you win!\n"
			elif  player == 2 and computer == 1:
				player_wins += 1
				return "you win!\n"
			elif player == 3 and computer == 2:
				player_wins += 1
				return "you win!\n"
			elif player == computer:
				return "tie game!\n"
			else:
				python_wins += 1
				return "python wins\n"

		game_result = decide_winner(player, computer)
		print(game_result)

		nonlocal game_count
		game_count += 1
		print("game count: " + str(game_count))
		print("Player wins: " + str(player_wins))
		print("Python wins: " + str(python_wins))

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
	return play_rps


play = rps()

play()

