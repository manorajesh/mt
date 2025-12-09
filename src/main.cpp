#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>

uint64_t now_ns() {
  static mach_timebase_info_data_t tb{};
  if (tb.denom == 0)
    mach_timebase_info(&tb);
  return mach_absolute_time() * tb.numer / tb.denom;
}

int main() {
  int master_fd, slave_fd;
  termios t{};
  winsize w{};

  if (openpty(&master_fd, &slave_fd, nullptr, &t, &w) == -1) {
    perror("openpty");
    return 1;
  }

  pid_t pid = fork();
  if (pid < 0) {
    perror("fork");
    return 1;
  }

  if (pid == 0) {
    // CHILD: raw echo server
    close(master_fd);

    dup2(slave_fd, STDIN_FILENO);
    dup2(slave_fd, STDOUT_FILENO);
    dup2(slave_fd, STDERR_FILENO);
    close(slave_fd);

    termios raw{};
    tcgetattr(STDIN_FILENO, &raw);
    cfmakeraw(&raw);
    tcsetattr(STDIN_FILENO, TCSANOW, &raw);

    char b;
    while (true) {
      if (read(STDIN_FILENO, &b, 1) == 1)
        write(STDOUT_FILENO, &b, 1);
    }
  }

  // PARENT
  close(slave_fd);
  fcntl(master_fd, F_SETFL, O_NONBLOCK);

  constexpr int trials = 1000;
  char send = 'A';
  char recv;

  uint64_t best = UINT64_MAX;
  uint64_t worst = 0;
  uint64_t total = 0;

  for (int i = 0; i < trials; i++) {
    uint64_t t0 = now_ns();

    if (write(master_fd, &send, 1) != 1) {
      perror("write");
      return 1;
    }

    while (true) {
      ssize_t n = read(master_fd, &recv, 1);
      if (n == 1)
        break;
    }

    uint64_t dt = now_ns() - t0;
    if (dt < best)
      best = dt;
    if (dt > worst)
      worst = dt;
    total += dt;
  }

  printf("Trials: %d\n", trials);
  printf("Best:   %.3f us\n", best / 1000.0);
  printf("Worst:  %.3f us\n", worst / 1000.0);
  printf("Avg:    %.3f us\n", (total / trials) / 1000.0);

  return 0;
}