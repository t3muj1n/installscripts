#!/usr/bin/env python3

myvar = 'hello world'
myvar2 = 'seasons greetings'
print("greetings")
print(myvar + ' ' + myvar2)



mathvar1=10
mathvar2=15

result=mathvar1 + mathvar2
print(result)


result=mathvar1 * mathvar2
print(result)

meaning = result > mathvar1
print(result)
print(meaning)
if result > mathvar1 :
	print("yay!")
else:
	print ("not greater than")

#ternary operator
print ('yay!') if result > mathvar1 else print('not greater than')


#check what datatype

print(type(mathvar1))
print(type(myvar2))


print(isinstance(myvar2,str))

