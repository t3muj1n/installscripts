#!/usr/bin/env python3 

from tkinter import *

root = Tk() #make root window
def MyClick(): #define function MyClick
	#display text and push to root window
	MyLabel = Label(root, text="label 1") 
	MyLabel.pack()

#call the myclick func
MyButton1= Button(root, text="click me!", command=MyClick) #this works
MyButton2= Button(root, text="click me2", command=MyClick()) #button does nothing
MyButton3= Button(root, text="click me3", command=MyClick, fg="blue", bg="#ffffff") #changes color

MyButton1.pack()
MyButton2.pack()
MyButton3.pack()
root.mainloop()
