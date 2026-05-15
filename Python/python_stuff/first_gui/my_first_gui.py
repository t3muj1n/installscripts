#!/usr/bin/env python3 

import tkinter as tk

window = tk.Tk()	#create a window. the root widget
label = tk.Label(
    text="Hello, Tkinter",	#text displayed
    width=10,
    height=10,
    foreground="white",  # Set the text color to white
    background="black",  # Set the background color to black
)
button = tk.Button(
    text="Click me!",
    width=10,
    height=10,
    bg="blue",
    fg="yellow",
)
entry = tk.Entry(
	fg="yellow",
	bg="blue",
	width=10
)


label.pack() #necessary to generate window from the objects above
button.pack()
entry.pack()
window.mainloop()	#keep window open