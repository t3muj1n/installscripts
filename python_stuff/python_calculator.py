#!/usr/bin/env python3 

from tkinter import *

root = Tk()
root.title("python calculator")

e = Entry(root, width=35, borderwidth=5)
e.grid(row=0, column=0, columnspan=3, padx=10, pady=10)

#define functions for what to do on button push
def b_click(number):
	current = e.get()
	e.delete(0, END)
	e.insert(0, str(current) + str(number))

def b_clear():
	e.delete(0, END)

def b_add():
	first_number = e.get()
	global firstnum 
	global math
	math = "addition"
	firstnum = int(first_number)
	e.delete(0, END)

def b_subtract():
	first_number = e.get()
	global firstnum 
	global math
	math = "subtraction"
	firstnum = int(first_number)
	e.delete(0, END)

def b_multiply():
	first_number = e.get()
	global firstnum 
	global math
	math = "multiplication"
	firstnum = int(first_number)
	e.delete(0, END)

def b_divide():
	first_number = e.get()
	global firstnum 
	global math
	math = "division"
	firstnum = int(first_number)
	e.delete(0, END)

def b_equal():
	second_number = e.get()
	e.delete(0, END)
	#if to determine what math operation to perform
	if math == "addition":
		e.insert(0, firstnum + int(second_number))
	if math == "subtraction":
		e.insert(0, firstnum - int(second_number))
	if math == "multiplication":
		e.insert(0, firstnum * int(second_number))
	if math == "division":
		e.insert(0, firstnum / int(second_number))


#define buttons
button1=Button(root, text="1", padx=40, pady=20, command=lambda: b_click(1))
button2=Button(root, text="2", padx=40, pady=20, command=lambda: b_click(2))
button3=Button(root, text="3", padx=40, pady=20, command=lambda: b_click(3))
button4=Button(root, text="4", padx=40, pady=20, command=lambda: b_click(4))
button5=Button(root, text="5", padx=40, pady=20, command=lambda: b_click(5))
button6=Button(root, text="6", padx=40, pady=20, command=lambda: b_click(6))
button7=Button(root, text="7", padx=40, pady=20, command=lambda: b_click(7))
button8=Button(root, text="8", padx=40, pady=20, command=lambda: b_click(8))
button9=Button(root, text="9", padx=40, pady=20, command=lambda: b_click(9))
button0=Button(root, text="0", padx=40, pady=20, command=lambda: b_click(0))
button_add=Button(root, text="+", padx=39, pady=20, command=b_add)
button_equal=Button(root, text="=", padx=92, pady=20, command=b_equal)
button_clear=Button(root, text="clear", padx=82, pady=20, command=b_clear)
button_subtract=Button(root, text="-", padx=41, pady=20, command=b_subtract)
button_multiply=Button(root, text="*", padx=41, pady=20, command=b_multiply)
button_divide=Button(root, text="/", padx=41, pady=20, command=b_divide)

#push buttons into root window
button1.grid(row=3, column=0)
button2.grid(row=3, column=1)
button3.grid(row=3, column=2)
button4.grid(row=2, column=0)
button5.grid(row=2, column=1)
button6.grid(row=2, column=2)
button7.grid(row=1, column=0)
button8.grid(row=1, column=1)
button9.grid(row=1, column=2)
button0.grid(row=4, column=0)
button_add.grid(row=5, column=0)
button_equal.grid(row=5, column=1, columnspan=2)
button_clear.grid(row=4, column=1, columnspan=2)
button_subtract.grid(row=6, column=0)
button_multiply.grid(row=6, column=1)
button_divide.grid(row=6, column=2)


root.mainloop()
