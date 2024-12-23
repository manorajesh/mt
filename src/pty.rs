use std::os::fd::{ IntoRawFd, RawFd };
use std::ffi::CString;
use std::io::{ BufReader, Read };
use std::thread;
use std::os::fd::FromRawFd;

use nix::fcntl::OFlag;
use nix::ioctl_write_int;
use nix::pty::ForkptyResult;
use nix::{ fcntl::{ fcntl, F_SETFL }, pty::forkpty, unistd::execv, sys::termios::Termios };
use winit::event_loop::EventLoopProxy;
use winit::window::Window;

use crate::ansi_parser::{ AnsiParser, AnsiSimdParser };
use crate::CustomEvent;

pub struct Pty {
    fd: RawFd,
}

impl Pty {
    pub fn new(
        proxy: EventLoopProxy<CustomEvent>,
        mut parser: AnsiSimdParser,
        rows: usize,
        cols: usize
    ) -> Self {
        let winsize = nix::pty::Winsize {
            ws_row: rows as u16,
            ws_col: cols as u16,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };

        let fork_result = (unsafe { forkpty(Some(&winsize), None) }).expect("Failed to fork pty");

        let master_fd = match fork_result {
            ForkptyResult::Parent { master, .. } => master.into_raw_fd(),
            ForkptyResult::Child { .. } => {
                // Child process: Execute the shell
                let shell = CString::new("/bin/zsh").expect("CString::new failed");
                let args = [shell.clone(), CString::new("-l").unwrap()];
                execv(&shell, &args).expect("execv failed");
                // If execv succeeds, the following lines won't be executed
                -1
            }
        };

        // Only the parent continues beyond this point
        let flags = OFlag::O_RDWR | OFlag::O_NONBLOCK;
        fcntl(master_fd, F_SETFL(flags)).expect("Failed to set flags");
        std::env::set_var("TERM", "xterm-256color");

        // Spawn a thread to read from the pty
        thread::spawn(move || {
            // Larger buffer size - 1MB
            let mut buf = [0u8; 1024 * 1024];

            loop {
                // Batch read multiple times before parsing
                let mut total_read = 0;
                for _ in 0..4 {
                    // Try up to 4 reads before processing
                    unsafe {
                        let n = libc::read(
                            master_fd,
                            buf.as_mut_ptr().add(total_read) as *mut _,
                            buf.len() - total_read
                        );

                        match n {
                            0 => {
                                return;
                            } // EOF
                            n if n > 0 => {
                                total_read += n as usize;
                                if total_read >= buf.len() / 2 {
                                    break; // Buffer getting full, process it
                                }
                            }
                            _ => {
                                // if *libc::__errno_location() == libc::EAGAIN {
                                //     break; // No more data available right now
                                // }
                                // return;
                            }
                        }
                    }
                }

                if total_read > 0 {
                    let data = &buf[..total_read];
                    parser.parse(data);
                    proxy.send_event(CustomEvent::RequestRedraw).expect("Failed to send event");
                }
            }
        });

        Pty {
            fd: master_fd,
            // buffer,
        }
    }

    pub fn resize(&self, rows: usize, cols: usize) {
        let winsize = nix::pty::Winsize {
            ws_row: rows as u16,
            ws_col: cols as u16,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };

        unsafe {
            libc::ioctl(self.fd, libc::TIOCSWINSZ, &winsize as *const _);
        }
    }

    pub fn write(&self, data: &[u8]) {
        unsafe {
            libc::write(self.fd, data.as_ptr() as *const _, data.len());
        }
    }
}
