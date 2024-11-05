#!/usr/bin/env python3 

from tkinter import *

root = Tk()
MyButton = Button(root, text="click me", state=DISABLED) 	#disabled button
MyButton2 = Button(root, text="click me") 					#enabled button
MyButton3 = Button(root, text="click me", padx=5, pady=5) 	#set size of button

#put buttons on screen in main root window
MyButton.pack() 
MyButton2.pack() 
MyButton3.pack()
root.mainloop()
