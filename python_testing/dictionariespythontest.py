#!/usr/bin/env python3

# dictonaries

band = {
	"vocals": "Plant",
	"guitar": "Page"
}

band2 = dict(vocals="plant", guitar="Page")

print(band)
print(band2)
print(type(band))
print(len(band2))

# access items in dict

print(band["vocals"])
print(band.get("guitar"))


# list all keys
print(band.keys())
# list all values
print(band.values())

# list of key value pairs as tuples

print(band.items())

# verify if key exists
print("guitar" in band)
print("triangle" in band)

# change values
band["vocals"] = "Coverdale"
print(band["vocals"])

band.update({"bass": "JPJ"})
print(band)

# remove items
print(band.pop("bass"))
print(band)
band["drums"] = "Bonhan"
print(band)

print(band.popitem()) #returns a tuple
print(band)
# delete and clear
band["drums"] = "Bonham"
del band["drums"]
print(band)

band2.clear() # prints {}
print(band2)
del band2


# band2 = band # creates a reference. refer to same place in mem or same dict
# print("bad copy!")
# print(band)
# print(band2)

# band2["drums"] ="Dave"
# print(band)
# print(band2)

band2 = band.copy()
band2["drums"] = "dave"
print("good copy!")
print(band)
print(band2)

# or dictionary cnstructor function

band3 = dict(band)
print("copy using dict()")
print(band3)


# nested dictionaries

member1 = {
	"name": "Plant",
	"instrument": "vocals"

}


member2 = {
	"name": "Page",
	"instrument": "guitar"
	
}
band = {
	"member1": member1,
	"member2": member2
}


print(band)
print(band["member1"]["name"])


# sets
# no duplicates allowed. it ignors the dup

nums = {1,2,3,4}
nums2 = set((1,2,3,4,5))
print(nums)
print(len(nums))
print(2 in nums)
# cannot refer to element in set w/ index or key

# add new value to set

nums.add(8)
print(nums)

# add elements from one set to another

morenums = {5,6,7}
nums.update(morenums)
print(nums)

# you can use update with lists, tuples, and dict

#merge two sets to creat a new set

one = {1,2,3}
two = {5,6,7}
mynewset = one.union(two)
print(mynewset)

# keep only the duplicates
one = {1,2,3}
two = {2,3,4}
one.intersection_update(two)
print(one)
# keep everything but dups
one = {1,2,3}
two = {2,3,4}
one.symmetric_difference_update(two)
print(one)