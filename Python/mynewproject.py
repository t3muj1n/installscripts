#!/usr/bin/env python3 

from tkinter import *

root = Tk() #make root window

#define some entry boxes
EntryBox1=Entry(root, width=50)
EntryBox2=Entry(root)
EntryBox3=Entry(root, width=50, bg="blue", fg="white")
EntryBox4=Entry(root, width=50, borderwidth=5)

#insert some text into entrybox
EntryBox1.insert(0, "entrybox1")
EntryBox2.insert(0, "entrybox2")
EntryBox3.insert(0, "entrybox3")
EntryBox4.insert(0, "entrybox4")

#pack entry boxes into root window
EntryBox1.pack()
EntryBox2.pack()
EntryBox3.pack()
EntryBox4.pack()



#define function MyClick
#funcions to do think on button click
def MyClick1(): 
	#display text and push to root window
	MyLabel = Label(root, text="text1" + EntryBox1.get()) 
	MyLabel.pack()

def MyClick2():
	MyLabel = Label(root, text="text2" + EntryBox2.get())
	MyLabel.pack()

def MyClick3():
	MyLabel = Label(root, text="text3" + EntryBox3.get())
	MyLabel.pack()

def MyClick4():
	hello = "hello " + EntryBox4.get()
	MyLabel = Label(root, text=hello)
	MyLabel.pack()

#call the myclick func
#MyButton2= Button(root, text="click me2", command=MyClick1()) #button does nothing
MyButton1= Button(root, text="click me1", command=MyClick1, state=DISABLED) #this works
MyButton2= Button(root, text="click me2", command=MyClick2)
MyButton3= Button(root, text="click me3", command=MyClick3, fg="blue", bg="#ffffff") #changes color
MyButton4= Button(root, text="click me4", command=MyClick4 ) #echos label from MyClick4 func

MyButton1.pack()
MyButton2.pack()
MyButton3.pack()
MyButton4.pack()

root.mainloop()
