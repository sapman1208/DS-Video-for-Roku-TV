#include <unistd.h>

extern char **environ;

int main(void) {
    char *argv[] = {
        "/usr/bin/python3",
        "/usr/syno/synoman/webapi/VideoStation/rokuvte.py",
        0
    };
    execve(argv[0], argv, environ);
    return 127;
}
