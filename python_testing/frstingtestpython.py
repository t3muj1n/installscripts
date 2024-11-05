#!/usr/bin/env python3
from datetime import datetime
name = "alice"
age = 30

old_format = "hello, name: {} and age: {} years".format(name, age)

f_string = f"hell, name: {name} and age: {age} years"
print("using fstring: ", f_string)

price = 1234.5678
print(f"the prise: ${price:.2f}")

large_number = 100000000
print(f"{large_number:,}")

now = datetime.now()
print(f"todays date: {now:%Y %m %d %H %M %S %s}")
print(now)



