/* CI probe: the emulator must set and read the real Linux socket mark. */
#include <sys/socket.h>
#include <unistd.h>
#include <stdint.h>
#include <stdio.h>

int main(void)
{
    const int families[] = { AF_INET, AF_INET6 };
    for (unsigned i = 0; i < sizeof(families) / sizeof(families[0]); i++) {
        int fd = socket(families[i], SOCK_DGRAM, 0);
        uint32_t mark = 134217728, actual = 0;
        socklen_t size = sizeof(actual);
        if (fd < 0 || setsockopt(fd, SOL_SOCKET, SO_MARK, &mark, sizeof(mark)) ||
            getsockopt(fd, SOL_SOCKET, SO_MARK, &actual, &size)) {
            perror("Linux SO_MARK");
            return 1;
        }
        close(fd);
        if (actual != mark) return 2;
    }
    puts("ARM64 IPv4/IPv6 SO_MARK reached the Linux kernel");
    return 0;
}
