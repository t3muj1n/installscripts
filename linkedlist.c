#!/usr/bin/tcc -run
// it has been a very long time since i wrote anything in C.
// i need to get back into writing more code i think. 
// this is a refresher for me on what from years ago.
// a linked list written in c. 
// if you leave the top line, and have tinyCC installed,
// this will run like a script
#include <stdio.h>
#include <stdlib.h>
int arg1 = 0;
typedef struct {
	void *next;
	int data;
} Node;

Node *head = NULL;

// add a node
Node *add_node(int data) {
	Node *new = NULL;
	if ( head == NULL) {
		new = malloc(sizeof(Node));
		if ( new == NULL) 
			return NULL;
		

		new->data = data;
		head = new;
		new->next = NULL;
	} else {
		new = malloc(sizeof(Node));
		if (new == NULL) 
			return NULL;
		
		new->data = data;
		new->next = head;
		head = new;
	}
	return new;
}

//remove node
int remove_node(int data) {
	Node *current = head;
		Node *prev = head;

	while (current != NULL) {
		if (current->data == data) {
			if (current == head) {
				head = current->next;
			} else {
				prev->next = current->next;
				free(current);
				current = NULL;
			}
			return 1;
		}
		prev = current;
		current = current->next;
	}
	return 0;
}

Node *insert_node(int data, int position) {
	Node *current = head;
	while ( current != NULL && position != 0) {
		position = position - 1;
	}
	if (position != 0) {
		printf("requested position too far.\n");
		return NULL;
	}

	Node *new = malloc(sizeof(Node));
	if (new == NULL)
		return NULL;

	new->data = data;
	new->next = current->next;
	current->next = new;

	return new;

}



void print_list() {
	
	Node *current = head;
	while (current != NULL) {
		printf("%d->", current->data);
		current = current->next;
	}
	printf("\n");
	return;
}

void print_menu() {
	printf("options\n");
	printf("\t1. add a node\n");
	printf("\t2. remove a node\n");
	printf("\t3. insert into node\n");
	printf("\t4. print list\n");
	printf("\t5. exit.\n");

}
int main(int argc, char **argv)
{
    int option = -1;
    int arg1 = 0;
    int arg2 = 0;
    while (option != 5)
    {
        print_menu();
        int num_received = scanf("%d", &option);
        if (num_received == 1 && option > 0 && option <= 5)
        {
            switch(option)
            {
                case 1:
                    // add operation
                    printf("What data should I insert?:\n");
                    scanf("%d", &arg1);
                    Node *new = add_node(arg1);
                    break;
                case 2:
                    // remove operation
                    printf("What data should I remove?:\n");
                    scanf("%d", &arg1);
                    int success = remove_node(arg1);
                    if (!success)
                        printf("Element not found\n");

                    break;
                case 3:
                    // insert operation
                    // remove operation
                    printf("What data should I insert?:\n");
                    scanf("%d", &arg1);
                    printf("What position?:\n");
                    scanf("%d", &arg2);
                    new = insert_node(arg1, arg2);
                    if (new == NULL)
                        printf("Failed to insert into list\n");
                    break;
                case 4:
                    // print the list
                    print_list();
                    break;
                case 5:
                    break;
            }
        }
    }
    

    return 0;
}
