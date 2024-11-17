//
//  Pty.swift
//  mt
//
//  Created by Mano Rajesh on 10/16/24.
//

import Foundation

class Pty {
    var masterFd: UnsafeMutablePointer<Int32> = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    var termiosOptions = termios()
    var buffer: Buffer
    var view: TerminalView
    var parser: AnsiParser
    
    init(buffer: Buffer, view: TerminalView, rows: UInt16, cols: UInt16) {
        self.buffer = buffer
        self.view = view
        self.parser = AnsiParser(buffer: buffer)
        var winSize = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        
        let pid = forkpty(masterFd, nil, &termiosOptions, &winSize)
        
        if pid == -1 {
            print("Error creating PTY")
            return
        } else if pid == 0 {
            // Child process: Execute the shell here
            let shell = "/bin/zsh"
            let args: [UnsafeMutablePointer<CChar>?] = [
                strdup(shell),
                nil
            ]
            execv(shell, args)
            exit(1)  // Exit if execv fails
        } else {
            // Parent process: Now you can use masterFd to communicate with the PTY
            let fd = masterFd.pointee
            
            // Set the file descriptor to non-blocking mode
            let flags = fcntl(fd, F_GETFL)
            fcntl(fd, F_SETFL, flags | O_NONBLOCK)
            
            // Start reading shell output and handling user input
            startReadingOutput(fd: fd)
        }
    }
    
    private func configureTermios() {
        // Turn off ICANON (disable canonical mode)
        termiosOptions.c_lflag &= ~UInt(ICANON)
        
        // Turn off ECHO (disable echoing of input characters)
        termiosOptions.c_lflag &= ~UInt(ECHO)
        
        // Enable signal generation (ISIG)
        termiosOptions.c_lflag |= UInt(ISIG)
        
        // Enable extended input processing (IEXTEN)
        termiosOptions.c_lflag |= UInt(IEXTEN)
        
        // Input flag: Enable carriage return to newline translation (ICRNL)
        termiosOptions.c_iflag |= UInt(ICRNL)
        
        // Output flag: Enable output post-processing (OPOST)
        termiosOptions.c_oflag |= UInt(OPOST)
        
        // Set the minimum number of characters for non-canonical reads (VMIN = 1)
//        termiosOptions.c_cc[VMIN] = 1
//        
//        // Set timeout for non-canonical reads to 0 (VTIME = 0)
//        termiosOptions.c_cc[VTIME] = 0
    }

    func resizePty(rows: UInt16, cols: UInt16) {
        var winSize = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        ioctl(self.masterFd.pointee, TIOCSWINSZ, &winSize)
    }
    
    // Start reading from PTY and updating the buffer with shell output
    private func startReadingOutput(fd: Int32) {
        let bufferSize = 1024
        var bufferArray = [UInt8](repeating: 0, count: bufferSize)
        
        DispatchQueue.global(qos: .userInteractive).async {
            while true {
                let bytesRead = read(fd, &bufferArray, bufferSize - 1)
                if bytesRead > 0 {
                    for i in 0..<bytesRead {
                        self.parser.parse(byte: bufferArray[i])
                    }
                    DispatchQueue.main.async {
                        // Redraw the view
                        //                        self.view.setNeedsDisplay(self.view.bounds)
                        self.view.refresh()
                    }
                }
                usleep(10000)  // 10ms delay to avoid busy-waiting
            }
        }
    }
    
    // Send user input to the PTY
    func sendInput(_ input: String) {
        let fd = masterFd.pointee
        let inputCStr = input.cString(using: .utf8)
        if let inputBytes = inputCStr {
            write(fd, inputBytes, strlen(inputBytes))
        }
    }
    
    func sendSpecialKey(_ key: SpecialKey) {
        let fd = masterFd.pointee
        var controlBytes: [UInt8] = []
        
        switch key {
        case .enter:
            controlBytes = [0x0A]  // Newline (Enter)
        case .ctrlC:
            controlBytes = [0x03]  // Ctrl+C
        case .ctrlD:
            controlBytes = [0x04]  // Ctrl+D
        case .ctrlZ:
            controlBytes = [0x1A]  // Ctrl+Z
        case .backspace:
            controlBytes = [0x08]  // Backspace (delete character)
            
            // Arrow keys send escape sequences:
        case .arrowUp:
            controlBytes = [0x1B, 0x5B, 0x41]  // ESC [ A
        case .arrowDown:
            controlBytes = [0x1B, 0x5B, 0x42]  // ESC [ B
        case .arrowLeft:
            controlBytes = [0x1B, 0x5B, 0x44]  // ESC [ D
        case .arrowRight:
            controlBytes = [0x1B, 0x5B, 0x43]  // ESC [ C
        }
        
        // Write the control sequence to the PTY
        write(fd, controlBytes, controlBytes.count)
    }
    
    deinit {
        masterFd.deallocate()
    }
}

enum SpecialKey {
    case enter
    case ctrlC
    case ctrlD
    case ctrlZ
    case backspace
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
}
