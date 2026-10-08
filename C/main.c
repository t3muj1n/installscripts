#!/usr/bin/tcc -run

#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>

struct Person {
    char name[64];
    int age;
};

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;

    struct Person people[100];
    struct Person *p = people;
    size_t count = sizeof(people) / sizeof(people[0]);

    puts("Initializing people via pointer arithmetic:");
    for (size_t i = 0; i < count; ++i) {
        struct Person *current = p + i;
        current->age = (int)(0 + i);
        snprintf(current->name, sizeof(current->name), "Person_%zu", i);

        printf("  index=%zu ptr=%p offset=%td name=%s age=%d\n",
               i,
               (void *)current,
               current - people,
               current->name,
               current->age);
    }

    puts("\nDirect element access using pointer math:");
    struct Person *forty_two = people + 2;
    forty_two->age += 10;
    printf("  (people + 2)->age = %d (people[2].age = %d)\n",
           (people + 2)->age,
           people[2].age);

    puts("\nPointer difference demonstration:");
    struct Person *end = people + count;
    ptrdiff_t traveled = end - people;
    printf("  end pointer:   %p\n", (void *)end);
    printf("  start pointer: %p\n", (void *)people);
    printf("  elements between start and end: %td\n", traveled);

    puts("\nConst pointer experiment:");
    const struct Person *const_ptr = people;
    printf("  const_ptr points at %p (name=%s age=%d)\n",
           (void *)const_ptr,
           const_ptr->name,
           const_ptr->age);
    const_ptr++;
    printf("  after const_ptr++ -> %p (name=%s age=%d)\n",
           (void *)const_ptr,
           const_ptr->name,
           const_ptr->age);

    puts("\nDynamic allocation with pointer traversal:");
    size_t dyn_count = 8;
    struct Person *dynamic_people = malloc(dyn_count * sizeof *dynamic_people);
    if (!dynamic_people) {
        fputs("  malloc failed\n", stderr);
        return 1;
    }

    struct Person *walker = dynamic_people;
    for (size_t i = 0; i < dyn_count; ++i) {
        walker->age = (int)(100 + i);
        snprintf(walker->name, sizeof(walker->name), "Heap_%zu", i);
        printf("  heap index=%zu ptr=%p name=%s age=%d\n",
               i,
               (void *)walker,
               walker->name,
               walker->age);
        walker++;
    }

    ptrdiff_t heap_span = walker - dynamic_people;
    printf("  walked across %td heap elements\n", heap_span);

    free(dynamic_people);

    return 0;
}
