//
//  pty.hpp
//  mt
//
//  Created by Mano Rajesh on 12/9/25.
//

#pragma once

#include <dispatch/dispatch.h>
#include <functional>
#include <cstddef>
#include <sys/types.h> // pid_t

class Pty {
public:
    Pty();
    ~Pty();
    
    Pty(const Pty&) = delete;
    Pty& operator=(const Pty&) = delete;
    
    // Start PTY + spawn shell. Pass initial rows/cols if you have them.
    bool start(int rows = 24, int cols = 80);
    
    // Resize the PTY (call on drawable/grid resize).
    bool setWinSize(int rows, int cols, int pxW = 0, int pxH = 0);
    
    // Send bytes to the child (keyboard input).
    void send(const char* data, std::size_t len);
    
    // Stop and clean up (safe to call multiple times).
    void stop();
    
    // Called on the PTY serial queue thread (the same queue as the dispatch_source).
    // Put your parser/core consume call here (no extra thread hop).
    std::function<void(const char*, std::size_t)> onOutput;
    
    int masterFd() const { return master_fd; }
    pid_t childPid() const { return shell_pid; }
    
private:
    int master_fd = -1;
    pid_t shell_pid = -1;
    dispatch_source_t ptySource = nullptr;
};
