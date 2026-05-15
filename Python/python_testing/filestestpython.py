#!/usr/bin/env python3

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
	