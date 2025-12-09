#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <fcntl.h>
#include <signal.h>
#include <termios.h>
#include <unistd.h>

#include <dispatch/dispatch.h> // GCD
#include <sys/ioctl.h>
#include <util.h> // openpty on macOS

// -----------------------------------------------------------------------------
// RAII helper to put stdin into raw mode and restore on exit
// -----------------------------------------------------------------------------
struct StdinRawMode {
  termios orig{};
  bool enabled = false;

  void enable() {
    if (tcgetattr(STDIN_FILENO, &orig) == -1) {
      perror("tcgetattr");
      return;
    }
    termios raw = orig;
    cfmakeraw(&raw);
    if (tcsetattr(STDIN_FILENO, TCSANOW, &raw) == -1) {
      perror("tcsetattr");
      return;
    }
    enabled = true;
  }

  void restore() {
    if (enabled) {
      tcsetattr(STDIN_FILENO, TCSANOW, &orig);
      enabled = false;
    }
  }

  ~StdinRawMode() { restore(); }
};

// -----------------------------------------------------------------------------
// Simple write-all helper
// -----------------------------------------------------------------------------
static void write_all(int fd, const char *buf, ssize_t n) {
  ssize_t off = 0;
  while (off < n) {
    ssize_t m = write(fd, buf + off, n - off);
    if (m > 0) {
      off += m;
    } else if (m == -1 && errno == EINTR) {
      continue;
    } else {
      break;
    }
  }
}

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------
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
    // CHILD: become the shell attached to the slave PTY.

    // Make this the controlling terminal
    close(master_fd);
    setsid();
    if (ioctl(slave_fd, TIOCSCTTY, 0) == -1) {
      perror("TIOCSCTTY");
      // continue anyway
    }

    dup2(slave_fd, STDIN_FILENO);
    dup2(slave_fd, STDOUT_FILENO);
    dup2(slave_fd, STDERR_FILENO);
    close(slave_fd);

    // Exec a login shell (change to zsh/fish if you prefer)
    execl("/bin/bash", "bash", "-l", (char *)nullptr);

    // If execl fails:
    perror("execl");
    _exit(1);
  }

  // PARENT: terminal emulator side.
  close(slave_fd);

  // Put our stdin into raw mode so we get key presses immediately.
  StdinRawMode raw_mode;
  raw_mode.enable();

  // Optional: make stdout unbuffered just in case.
  setvbuf(stdout, nullptr, _IONBF, 0);

  // Queue for our dispatch sources (serial).
  dispatch_queue_t q =
      dispatch_queue_create("mini_term_queue", DISPATCH_QUEUE_SERIAL);

  // ----- Source for PTY -> stdout -----
  dispatch_source_t pty_src =
      dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, master_fd, 0, q);

  if (!pty_src) {
    fprintf(stderr, "failed to create pty dispatch source\n");
    return 1;
  }

  dispatch_source_set_event_handler(pty_src, ^{
    char buf[4096];
    ssize_t n = read(master_fd, buf, sizeof(buf));
    if (n > 0) {
      write_all(STDOUT_FILENO, buf, n);
    } else if (n == 0) {
      // EOF from child – exit.
      dispatch_source_cancel(pty_src);
    } else if (errno != EINTR) {
      perror("read pty");
      dispatch_source_cancel(pty_src);
    }
  });

  dispatch_source_set_cancel_handler(pty_src, ^{
    close(master_fd);
    // When PTY is gone, exit the process.
    // stdin raw mode will be restored by RAII destructor.
    exit(0);
  });

  dispatch_resume(pty_src);

  // ----- Source for stdin -> PTY -----
  dispatch_source_t stdin_src =
      dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, q);

  if (!stdin_src) {
    fprintf(stderr, "failed to create stdin dispatch source\n");
    return 1;
  }

  dispatch_source_set_event_handler(stdin_src, ^{
    char buf[4096];
    ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
    if (n > 0) {
      write_all(master_fd, buf, n);
    } else if (n == 0) {
      // User closed stdin (e.g. ctrl-d on some setups) – close PTY.
      dispatch_source_cancel(stdin_src);
      dispatch_source_cancel(pty_src);
    } else if (errno != EINTR) {
      perror("read stdin");
      dispatch_source_cancel(stdin_src);
      dispatch_source_cancel(pty_src);
    }
  });

  dispatch_source_set_cancel_handler(
      stdin_src, ^{
          // Nothing special; RAII will restore terminal mode on exit.
      });

  dispatch_resume(stdin_src);

  // Ignore SIGINT so ctrl-c gets sent into the child shell instead.
  signal(SIGINT, SIG_IGN);

  // Hand control to GCD. This never returns.
  dispatch_main();
}