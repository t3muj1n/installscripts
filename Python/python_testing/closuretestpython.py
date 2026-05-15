#!/usr/bin/env python3

#closure is a function having access to the scope of its parent # function after the parent function has returned.


def parent_function(person):
	coins = 3

	def play_game():
		nonlocal coins
		coins -= 1
		if coins > 1:
			print(person + " has " + str(coins) + " coins left\n")
		elif coins == 1:
			print(person + " has " + str(coins) + " coin left\n")
		else:
			print(person + " is out of coins. \n")
	return play_game
	#returns itself

tommy = parent_function("Tommy")
james = parent_function("james")

tommy()
tommy()
james()
tommy()
james()
