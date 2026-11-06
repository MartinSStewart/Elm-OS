//! Talking to the GPU renderer, /usr/bin/elmos-gpu (host/gpu). /init is one static
//! binary, and Mesa's drivers are shared libraries that can't be loaded into it, so
//! the renderer is its own dynamically linked program that owns the display.
//!
//!   its stdin  <- frames: u32 count, then that many Tri (common/src/atlas.rs)
//!   its stdout -> "ok W H CURSOR RENDERER" once the display is up; then "f GPU_NS"
//!                 for each frame shown, or "d" for one skipped
//!   its fd 3   <- cursor commands: "m X Y" moves it, "c RGBA S" redraws it

use common::atlas::Tri;
use std::fs::File;
use std::io::{Read, Write};
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};

const GPU_RENDERER: &str = "/usr/bin/elmos-gpu";

pub struct Gpu {
    child: Child,
    frames: File,
    acks: Option<File>,
    cursor: File,
    pub w: u32,
    pub h: u32,
    /// The renderer drew the cursor on a cursor plane.
    pub cursor_plane: bool,
    pub name: String,
    ack_buf: Vec<u8>,
}

fn pipe() -> Option<(File, File)> {
    let mut fds = [0; 2];
    // SAFETY: fills in two file descriptors.
    if unsafe { libc::pipe2(fds.as_mut_ptr(), libc::O_CLOEXEC) } < 0 {
        return None;
    }
    // SAFETY: we own both new descriptors.
    Some(unsafe { (File::from_raw_fd(fds[0]), File::from_raw_fd(fds[1])) })
}

fn set_nonblocking(f: &File) {
    // SAFETY: fcntl on a descriptor we own.
    unsafe {
        let flags = libc::fcntl(f.as_raw_fd(), libc::F_GETFL);
        libc::fcntl(f.as_raw_fd(), libc::F_SETFL, flags | libc::O_NONBLOCK);
    }
}

impl Gpu {
    /// Starts the renderer and waits for it to report "ok W H CURSOR RENDERER".
    pub fn start(software_cursor: bool) -> Option<Gpu> {
        if std::env::var("ELMOS_RENDERER").as_deref() == Ok("cpu") {
            return None;
        }
        if !std::path::Path::new(GPU_RENDERER).exists() {
            return None;
        }
        let (cursor_read, cursor_write) = pipe()?;
        let cursor_fd = cursor_read.as_raw_fd();
        let mut cmd = Command::new(GPU_RENDERER);
        cmd.stdin(Stdio::piped()).stdout(Stdio::piped());
        if std::env::var_os("MESA_SHADER_CACHE_DISABLE").is_none() {
            cmd.env("MESA_SHADER_CACHE_DISABLE", "true"); // there is no disk to cache on
        }
        // SAFETY: only dup2 between fork and exec.
        unsafe {
            cmd.pre_exec(move || {
                if libc::dup2(cursor_fd, 3) < 0 {
                    return Err(std::io::Error::last_os_error());
                }
                Ok(())
            });
        }
        let mut child = match cmd.spawn() {
            Ok(c) => c,
            Err(e) => {
                log!("host", "spawn {}: {}", GPU_RENDERER, e);
                return None;
            }
        };
        drop(cursor_read);
        // SAFETY: we take ownership of the child's pipes.
        let frames = unsafe { File::from_raw_fd(std::os::fd::IntoRawFd::into_raw_fd(child.stdin.take()?)) };
        let mut out = unsafe { File::from_raw_fd(std::os::fd::IntoRawFd::into_raw_fd(child.stdout.take()?)) };

        // Loading Mesa can take a while under emulation.
        let mut line = Vec::new();
        let mut byte = [0u8; 1];
        loop {
            let mut pfd = [crate::sys::pollfd(out.as_raw_fd())];
            crate::sys::poll(&mut pfd, std::time::Duration::from_secs(60));
            if pfd[0].revents == 0 || line.len() >= 255 {
                break;
            }
            match out.read(&mut byte) {
                Ok(1) if byte[0] != b'\n' => line.push(byte[0]),
                _ => break,
            }
        }
        let line = String::from_utf8_lossy(&line).into_owned();
        let mut parts = line.splitn(5, ' ');
        let parsed = (|| {
            if parts.next()? != "ok" {
                return None;
            }
            let w = parts.next()?.parse().ok()?;
            let h = parts.next()?.parse().ok()?;
            let hw: i32 = parts.next()?.parse().ok()?;
            Some((w, h, hw != 0, parts.next().unwrap_or("").to_string()))
        })();
        let Some((w, h, plane, name)) = parsed else {
            log!(
                "host",
                "GPU renderer unavailable ({}); drawing on the CPU",
                if line.is_empty() { "no answer" } else { &line }
            );
            let _ = child.kill();
            let _ = child.wait();
            return None;
        };
        let mut gpu = Gpu {
            child,
            frames,
            acks: None,
            cursor: cursor_write,
            w,
            h,
            cursor_plane: plane && !software_cursor,
            name,
            ack_buf: Vec::new(),
        };
        set_nonblocking(&gpu.cursor);
        if plane && software_cursor {
            gpu.cursor_command("m -100 -100\n"); // hide it off screen
        }
        log!(
            "host",
            "{}",
            if gpu.cursor_plane {
                "cursor on the cursor plane"
            } else {
                "no cursor plane; Elm draws the cursor"
            }
        );
        log!("host", "display {}x{} on the GPU ({})", w, h, gpu.name);
        set_nonblocking(&out);
        gpu.acks = Some(out);
        Some(gpu)
    }

    pub fn pid(&self) -> u32 {
        self.child.id()
    }

    /// The fd that is readable when the renderer has shown or skipped frames.
    pub fn ack_fd(&self) -> i32 {
        self.acks.as_ref().map_or(-1, |f| f.as_raw_fd())
    }

    /// Hands a frame over. False if the renderer is gone.
    pub fn send_frame(&mut self, tris: &[Tri]) -> bool {
        let n = tris.len() as u32;
        self.frames.write_all(&n.to_ne_bytes()).is_ok() && self.frames.write_all(Tri::as_bytes(tris)).is_ok()
    }

    /// Non-blocking: if the pipe is backed up, skip it (the next move fixes the position).
    fn cursor_command(&mut self, line: &str) {
        let _ = self.cursor.write(line.as_bytes());
    }

    pub fn cursor_move(&mut self, x: i32, y: i32) {
        self.cursor_command(&format!("m {x} {y}\n"));
    }

    pub fn cursor_redraw(&mut self, fill: u32, scale: usize) {
        self.cursor_command(&format!("c {fill} {scale}\n"));
    }

    /// Reads the renderer's "f GPU_NS" (shown) and "d" (skipped) lines. Returns how
    /// many frames it is done with, and the GPU times it reported.
    pub fn read_acks(&mut self, gpu_ns: &mut Vec<f64>) -> u32 {
        let mut done = 0;
        let Some(acks) = self.acks.as_mut() else { return 0 };
        let mut buf = [0u8; 256];
        loop {
            match acks.read(&mut buf) {
                Ok(0) => {
                    // It exited; the next frame we send it finds out.
                    self.acks = None;
                    break;
                }
                Ok(n) => self.ack_buf.extend_from_slice(&buf[..n]),
                Err(_) => break,
            }
        }
        while let Some(nl) = self.ack_buf.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = self.ack_buf.drain(..=nl).collect();
            let line = String::from_utf8_lossy(&line[..nl]);
            if let Some(ns) = line.strip_prefix("f ") {
                done += 1;
                if let Ok(ns) = ns.trim().parse::<i64>() {
                    if ns >= 0 {
                        gpu_ns.push(ns as f64);
                    }
                }
            } else if line.starts_with('d') {
                done += 1;
            }
        }
        if self.ack_buf.len() > 4096 {
            self.ack_buf.clear(); // a line too long to be ours
        }
        done
    }
}

impl Drop for Gpu {
    fn drop(&mut self) {
        // SAFETY: signalling our own child.
        unsafe { libc::kill(self.child.id() as i32, libc::SIGTERM) };
        let _ = self.child.wait(); // it must let go of the display before we take it
    }
}
