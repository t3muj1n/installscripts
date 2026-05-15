#!/usr/bin/env python3

#literal assignment
first = "firstname"
last =  'lastname'

print(type(first))
print(type(last))

# string constructor
mypizza = str("Pepperoni")
print(type(mypizza))
print(type(mypizza) == str )
print(isinstance(first,str))


#concatination
fullname = first + " " + last
print (fullname)

fullname += "!!"
print (fullname)


#casting a number to a string
#cast num to string
mystring1 =str(1989)
print(type(mystring1))
print(mystring1)

output = "this is the string of a number cast to str: " + mystring1 + "\n"
print(output)

#multiline
multiline = '''
hello 
world
!

'''

print(multiline)


#########################
layout = "*" * 20
print(layout)
print()
another_quote = "Learning Python is fun!"
print(len(another_quote))
print()
print(another_quote[10])
print(another_quote[5:11])
print(another_quote[:])
print(another_quote[:11])
print(another_quote[11:])
print(another_quote[::-1])
print(another_quote.upper())
print(another_quote.lower())
print(another_quote.title())
print(another_quote.swapcase())
# lstrip() strips spaces left side rstrip() is right side .strip()?
#print(hello.replace( souce, replacestring))
#.find("string")
#.index(string)
#.count(string or char)
#.startswith()
#.endswith()
#.isalpha() .isdigit() .isalnum()
#.split() .split("!") or any char
#print("-".join(listofwords))

