#!/usr/bin/env python3 

from tkinter import *

root = Tk()

#create a Label widget
myLabel1 = Label(root, text="hello world!")
mtLabel2 = Label(root, text="myname is tem")
#shove it onto the screen
#myLabel.pack()
#root.mainloop()

myLabel1.grid(row = 0, column = 0)
mtLabel2.grid(row = 1, column = 1)
