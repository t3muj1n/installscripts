#!/usr/local/bin/tcc -run
#include <stdio.h>

struct Person
{
	char name[64];
	int age;

};

int main (int argc, char *argv[])
{
	struct Person people[100];
	struct Person *p_Person = &people;

	int i = 0;
	for (i = 0 ; i < 100; i++)
	{
		p_Person->age = 0;
		p_Person += 1;
		p_Person->name[0] = 0;


	}
	return 0;

}






/* I think the best way to explain this is that the pointer has a type, and that's why it multiplies it. If you were using a void pointer then you would need to get sizeof(person), but since the pointer is declared with a type, you don't need to do anything else.
*/


