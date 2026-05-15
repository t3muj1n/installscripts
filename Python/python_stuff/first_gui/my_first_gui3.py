#!/usr/bin/env python3 

from tkinter import *

root = Tk()

#create a Label widget
MyLabel1 = Label(root, text="label 1").grid(row=0, column=0)
MyLabel2 = Label(root, text="label 2").grid(row=0, column=1)
MyLabel3 = Label(root, text="label 3").grid(row=0, column=2)
MyLabel4 = Label(root, text="label 4").grid(row=0, column=3)
#shove it onto the screen
#myLabel.pack()
#root.mainloop()
root.mainloop()

