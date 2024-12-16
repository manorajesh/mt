//
//  Pty.swift
//  mt
//
//  Created by Mano Rajesh on 10/16/24.
//

import Foundation

class Pty {
    private let fd: Int32
    private var termiosOptions = termios()
    private let readQueue = DispatchQueue(label: "com.example.Pty.readQueue")
    
    private var buffer: Buffer
    private var view: TerminalView
    private var parser: AnsiParser
    
    init(buffer: Buffer, view: TerminalView, rows: UInt16, cols: UInt16) {
        self.buffer = buffer
        self.view = view
        self.parser = AnsiParser(buffer: buffer)
        
        var masterFd: Int32 = 0
        var winSize = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        
        let pid = forkpty(&masterFd, nil, &termiosOptions, &winSize)
        
        if pid == -1 {
            print("Error creating PTY")
            self.fd = -1
            return
        }
        
        self.fd = masterFd
        
        if pid == 0 {
            // Child process: Execute shell
            let shell = "/bin/zsh"
            let args: [UnsafeMutablePointer<CChar>?] = [strdup(shell), nil]
            execv(shell, args)
            exit(1)  // If execv fails
        } else {
            // Parent process: configure FD and start reading
            let flags = fcntl(fd, F_GETFL)
            fcntl(fd, F_SETFL, flags | O_NONBLOCK)
            startReadingOutput()
        }
    }
    
    private func configureTermios() {
        termiosOptions.c_lflag &= ~UInt(ICANON)
        termiosOptions.c_lflag &= ~UInt(ECHO)
        termiosOptions.c_lflag |= UInt(ISIG)
        termiosOptions.c_lflag |= UInt(IEXTEN)
        termiosOptions.c_iflag |= UInt(ICRNL)
        termiosOptions.c_oflag |= UInt(OPOST)
    }
    
    func resizePty(rows: UInt16, cols: UInt16) {
        var winSize = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        ioctl(self.fd, TIOCSWINSZ, &winSize)
    }
    
    private func startReadingOutput() {
        let bufferSize = 1024
        var bufferArray = [UInt8](repeating: 0, count: bufferSize)
        
        readQueue.async { [weak self] in
            guard let self = self else { return }
            
            while true {
                let bytesRead = read(self.fd, &bufferArray, bufferSize - 1)
                if bytesRead > 0 {
                    // Parse on the same queue to avoid data races
                    for i in 0..<bytesRead {
                        self.parser.parse(byte: bufferArray[i])
                    }
                    
                    let localView = self.view
                    
                    // Explicitly hop to main thread for UI refresh
                    DispatchQueue.main.async {
                        localView.refresh()
                    }
                }
                usleep(10)   // 10ms delay to avoid busy-waiting
            }
        }
    }
    
    // Thread-safe since writing to the fd does not conflict with parsing output
    func sendInput(_ input: String) {
        let inputCStr = input.cString(using: .utf8)!
        write(fd, inputCStr, strlen(inputCStr))
    }
    
    func sendSpecialKey(_ key: SpecialKey) {
        var controlBytes: [UInt8] = []
        switch key {
        case .enter:
            controlBytes = [0x0A]
        case .ctrlC:
            controlBytes = [0x03]
        case .ctrlD:
            controlBytes = [0x04]
        case .ctrlZ:
            controlBytes = [0x1A]
        case .backspace:
            controlBytes = [0x08]
        case .arrowUp:
            controlBytes = [0x1B, 0x5B, 0x41]
        case .arrowDown:
            controlBytes = [0x1B, 0x5B, 0x42]
        case .arrowLeft:
            controlBytes = [0x1B, 0x5B, 0x44]
        case .arrowRight:
            controlBytes = [0x1B, 0x5B, 0x43]
        }
        write(fd, controlBytes, controlBytes.count)
    }
}

enum SpecialKey {
    case enter, ctrlC, ctrlD, ctrlZ, backspace
    case arrowUp, arrowDown, arrowLeft, arrowRight
}
