//
//  Pty.cpp
//  mt
//
//  Created by Mano Rajesh on 12/9/25.
//

#include "pty.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <signal.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>
#include <fcntl.h>
#include <errno.h>

Pty::Pty() {}

Pty::~Pty() {
    stop();
}

void Pty::stop() {
    // Stop source first so no more handler calls happen.
    if (ptySource) {
        dispatch_source_cancel(ptySource);
        // cancel handler will close FD
        ptySource = nullptr;
    } else if (master_fd >= 0) {
        close(master_fd);
        master_fd = -1;
    }
    
    // Reap child (and kill process group if still running).
    if (shell_pid > 0) {
        // Send SIGHUP or SIGTERM first; SIGTERM is fine.
        kill(-shell_pid, SIGTERM);
        usleep(100000);
        kill(-shell_pid, SIGKILL);
        
        // Best-effort reap (avoid zombies)
        int status = 0;
        (void)waitpid(shell_pid, &status, WNOHANG);
        shell_pid = -1;
    }
}

static void set_cloexec(int fd) {
    int flags = fcntl(fd, F_GETFD);
    if (flags >= 0) (void)fcntl(fd, F_SETFD, flags | FD_CLOEXEC);
}

static void set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL);
    if (flags >= 0) (void)fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

bool Pty::start(int rows, int cols) {
    int slave_fd = -1;
    termios t{};
    winsize w{};
    w.ws_row = (unsigned short)(rows > 0 ? rows : 24);
    w.ws_col = (unsigned short)(cols > 0 ? cols : 80);
    
    if (openpty(&master_fd, &slave_fd, nullptr, &t, &w) == -1) {
        perror("openpty");
        return false;
    }
    
    set_cloexec(master_fd);
    // With dispatch_source, nonblocking is recommended (handler can be called spuriously).
    set_nonblocking(master_fd);
    
    pid_t pid = fork();
    if (pid < 0) {
        perror("fork");
        close(master_fd); master_fd = -1;
        close(slave_fd);
        return false;
    }
    
    if (pid == 0) {
        // CHILD
        close(master_fd);
        
        // New session, controlling terminal
        setsid();
        ioctl(slave_fd, TIOCSCTTY, 0);
        
        const char* home = getenv("HOME");
        if (home) chdir(home);
        
        setenv("TERM", "xterm-256color", 1);
        setenv("COLORTERM", "truecolor", 1);
        setenv("TERM_PROGRAM", "mt", 1);
        setenv("TERM_PROGRAM_VERSION", "1.0", 1);
        
        // Make the child the leader of its process group (so parent can kill -pid)
        setpgid(0, 0);
        
        dup2(slave_fd, STDIN_FILENO);
        dup2(slave_fd, STDOUT_FILENO);
        dup2(slave_fd, STDERR_FILENO);
        if (slave_fd > STDERR_FILENO) close(slave_fd);
        
        // Env that many programs expect
        setenv("TERM", "xterm-256color", 1);
        setenv("COLORTERM", "truecolor", 1);
        
        // Prefer $SHELL if you want:
        const char* shell = getenv("SHELL");
        if (!shell) shell = "/bin/zsh";
        execlp(shell, shell, "-l", (char*)nullptr);
        
        perror("execl");
        _exit(127);
    }
    
    // PARENT
    shell_pid = pid;
    close(slave_fd);
    
    // Create a serial queue: THIS is now your PTY+parser thread.
    // Do parsing here to avoid thread-hops.
    dispatch_queue_t q =
    dispatch_queue_create("com.mt.ptyqueue", DISPATCH_QUEUE_SERIAL);
    
    ptySource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, master_fd, 0, q);
    if (!ptySource) {
        fprintf(stderr, "dispatch_source_create failed\n");
        close(master_fd); master_fd = -1;
        return false;
    }
    
    // IMPORTANT: avoid capturing raw `this` if object might die before cancel finishes.
    // If your Pty truly lives for app lifetime, it's fine, but safer:
    Pty* self = this;
    
    dispatch_source_set_event_handler(ptySource, ^{
        // Drain until EAGAIN so we don't miss data.
        for (;;) {
            uint8_t buf[16384];
            ssize_t n = read(self->master_fd, buf, sizeof(buf));
            if (n > 0) {
                if (self->onOutput) {
                    // SPEC CHANGE: onOutput should DO THE PARSING here (same queue/thread).
                    self->onOutput((const char*)buf, (size_t)n);
                }
                continue;
            }
            if (n == 0) {
                printf("[mtCore] child exited (EOF)\n");
                dispatch_source_cancel(self->ptySource);
                break;
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                break;
            }
            if (errno == EINTR) {
                continue;
            }
            perror("[mtCore] read");
            dispatch_source_cancel(self->ptySource);
            break;
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

bool Pty::setWinSize(int rows, int cols, int pxW, int pxH) {
    if (master_fd < 0) return false;
    winsize w{};
    w.ws_row = (unsigned short)rows;
    w.ws_col = (unsigned short)cols;
    w.ws_xpixel = (unsigned short)pxW;
    w.ws_ypixel = (unsigned short)pxH;
    if (ioctl(master_fd, TIOCSWINSZ, &w) != 0) return false;
    if (shell_pid > 0) (void)kill(shell_pid, SIGWINCH);
    return true;
}

void Pty::send(const char *data, size_t len) {
    if (master_fd < 0 || !data || len == 0) return;
    
    size_t off = 0;
    while (off < len) {
        ssize_t n = write(master_fd, data + off, len - off);
        if (n > 0) { off += (size_t)n; continue; }
        if (n < 0 && errno == EINTR) continue;
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) continue; // or yield/sleep
        break;
    }
}
