#!/usr/bin/env python3

class TutorApp:

	def __init__(self):
		self.tutors = []

	def add_tutor(self):
		name = input("enter tutors name:\n")
		subject = input("enter subject taught by tutor:\n")
		rate = float(input("enter hourly rate:\n"))
		self.tutors.append(Tutor(name, subject, rate))
		print(f"tutor {name} added successfully.")

	def search_tutor(self):
		subject = input("enter subject to search for:\n")
		found_tutors = [tutor for tutor in self.tutors if tutor.subject.lower() == subject.lower() == subject.lower()]

		if found_tutors:
			print("tutors found:\n")

			for tutor in found_tutors:
				print(tutor)
		else:
			print("no tutors found for given subject.")

	def disply_tutors(self):
		if self.tutors:
			print("all tutors:\n")

			for tutor in self.tutors:
				print(tutor)

		else:
			print("no tutors available.")

	def run(self):

		while True:
			print("\n--- Tutor Search App ---")
			print("1. add tutor")
			print("2. search tutor")
			print("3. display all tutors")
			print("4. exit.")
			choice = input("enter your choice:\n")

			if choice =='1':
				self.add_tutor()

			elif choice == 2:
				self.search_tutor()

			elif choice == 3:
				self.display_tutor()

			elif choice == 4:
				print("exiting the app.")
				break

			else:
				print("invalid choice")


if __name__ == "__main__":
	app = TutorApp()
	app.run()



