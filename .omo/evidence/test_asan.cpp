#include <cstdio>
int main() {
    int* p = new int[10];
    p[20] = 42;  // OOB write
    printf("p[20] = %d\n", p[20]);
    delete[] p;
    return 0;
}
