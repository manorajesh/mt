//
//  mtCore.cpp
//  mt
//
//  Created by Mano Rajesh on 12/9/25.
//

#include "mtCore.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>

mtCore::mtCore() {}

mtCore::~mtCore() {
  if (ptySource) {
    dispatch_source_cancel(ptySource);
    // cancel handler will close the FD
  } else if (master_fd >= 0) {
    close(master_fd);
  }
}

bool mtCore::start() {
  int slave_fd;
  termios t{};
  winsize w{};

  if (openpty(&master_fd, &slave_fd, nullptr, &t, &w) == -1) {
    perror("openpty");
    return false;
  }

  pid_t pid = fork();
  if (pid < 0) {
    perror("fork");
    return false;
  }

  if (pid == 0) {
    // CHILD: shell
    close(master_fd);
    setsid();
    ioctl(slave_fd, TIOCSCTTY, 0);

    dup2(slave_fd, STDIN_FILENO);
    dup2(slave_fd, STDOUT_FILENO);
    dup2(slave_fd, STDERR_FILENO);
    close(slave_fd);

    execl("/bin/bash", "bash", "-l", (char *)nullptr);
    perror("execl");
    _exit(1);
  }

  // PARENT
  close(slave_fd);

  dispatch_queue_t q =
      dispatch_queue_create("com.mt.ptyqueue", DISPATCH_QUEUE_SERIAL);

  ptySource =
      dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, master_fd, 0, q);
  if (!ptySource) {
    fprintf(stderr, "dispatch_source_create failed\n");
    return false;
  }

  // Capture `this` safely (we know process lifetime == app lifetime here).
  mtCore *self = this;

  dispatch_source_set_event_handler(ptySource, ^{
    char buf[4096];
    ssize_t n = read(self->master_fd, buf, sizeof(buf));
    if (n > 0) {
      if (self->onOutput) {
        self->onOutput(buf, static_cast<size_t>(n));
      } else {
        // Fallback: log to console
        fwrite(buf, 1, n, stdout);
      }
    } else if (n == 0) {
      printf("[mtCore] child exited\n");
      dispatch_source_cancel(self->ptySource);
    }
  });

  dispatch_source_set_cancel_handler(ptySource, ^{
    if (self->master_fd >= 0) {
      close(self->master_fd);
      self->master_fd = -1;
    }
    printf("[mtCore] PTY closed\n");
  });

  dispatch_resume(ptySource);
  return true;
}

void mtCore::send(const char *data, size_t len) {
  if (master_fd < 0)
    return;
  ssize_t n = write(master_fd, data, len);
  (void)n;
}
