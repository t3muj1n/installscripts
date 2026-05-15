#!/usr/bin/env python3 

from datetime import datetime

# 1. keep the name short and concise
# 2. specify the return type
# 3. make it as simple and reusable as possible
# 4. document all your functions
# 5. handle errors 

def get_time() -> str: 
	now: datetime = datetime.now()
	return f'{now:%X}'

print(get_time())


