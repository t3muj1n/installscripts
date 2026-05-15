#!/usr/bin/env python3 

from tkinter import *

root = Tk() #make root window

#define some entry boxes
EntryBox1=Entry(root, width=50)
EntryBox2=Entry(root)
EntryBox3=Entry(root, width=50, bg="blue", fg="white")
EntryBox4=Entry(root, width=50, borderwidth=5)
#pack entry boxes into root window
EntryBox1.pack()
EntryBox2.pack()
EntryBox3.pack()
EntryBox4.pack()


#define function MyClick
def MyClick(): 
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
