//! What the debug overlay shows, sent twice a second:
//!
//!   {"t":"stats","cores":N,"cpu":P,"cpuElm":P,"cpuHost":P,"cpuGpu":P,
//!    "memUsed":MB,"memTotal":MB,"gpuMs":MS,"elmMs":MS,"drawMs":MS}
//!
//! cpu: all cores; cpuElm/Host/Gpu: % of one core used by the Elm program's process,
//! the host's (/init, all its threads), and elmos-gpu's. The times are averages per frame (-1 if unknown):
//! GPU time, how long Elm took to answer a frame, and how long /init took to draw it
//! (CPU) or pass it on (GPU).

use protocol::ToElm;

use crate::sys;

#[derive(Default)]
pub struct Stats {
    pub gpu_ns: Vec<f64>,
    pub elm: Vec<f64>,  // seconds Elm took to answer
    pub draw: Vec<f64>, // seconds we took to draw
    last_busy: u64,
    last_total: u64,
    last_ticks: [i64; 3],
    last_t: f64,
}

/// CPU ticks (user + system) a /proc/.../stat file reports.
fn proc_ticks(path: &str) -> Option<i64> {
    let s = std::fs::read_to_string(path).ok()?;
    let after = &s[s.rfind(')')? + 2..]; // the name can hold spaces
    let f: Vec<&str> = after.split_whitespace().collect();
    // state is field 0 here; utime and stime are fields 11 and 12
    Some(f.get(11)?.parse::<i64>().ok()? + f.get(12)?.parse::<i64>().ok()?)
}

fn average(v: &mut Vec<f64>, scale: f64) -> f64 {
    let r = if v.is_empty() {
        -1.0
    } else {
        v.iter().sum::<f64>() / v.len() as f64 * scale
    };
    v.clear();
    r
}

impl Stats {
    pub fn new() -> Stats {
        let mut s = Stats::default();
        s.cpu_load();
        s
    }

    /// CPU load since the last call, from /proc/stat, in percent.
    fn cpu_load(&mut self) -> f64 {
        let Ok(s) = std::fs::read_to_string("/proc/stat") else {
            return 0.0;
        };
        let Some(line) = s.lines().next() else { return 0.0 };
        let v: Vec<u64> = line
            .split_whitespace()
            .skip(1)
            .take(8)
            .filter_map(|x| x.parse().ok())
            .collect();
        if v.len() < 4 {
            return 0.0;
        }
        let total: u64 = v.iter().sum();
        let busy = total - v[3] - v.get(4).copied().unwrap_or(0); // minus idle and iowait
        let load = if total > self.last_total {
            100.0 * busy.saturating_sub(self.last_busy) as f64 / (total - self.last_total) as f64
        } else {
            0.0
        };
        self.last_busy = busy;
        self.last_total = total;
        load
    }

    /// Where the CPU time goes, in percent of one core since the last call: the Elm
    /// program, the host (/init), and elmos-gpu. A process that has just started counts
    /// from zero.
    fn cpu_split(&mut self, gpu_pid: Option<u32>) -> [f64; 3] {
        let mut ticks = [0i64; 3];
        for (i, pid) in [elm::pid(), Some(std::process::id()), gpu_pid].into_iter().enumerate() {
            if let Some(t) = pid.and_then(|p| proc_ticks(&format!("/proc/{p}/stat"))) {
                ticks[i] = t;
            }
        }
        let t = sys::now();
        // SAFETY: plain system call.
        let hz = unsafe { libc::sysconf(libc::_SC_CLK_TCK) } as f64;
        let span = t - self.last_t;
        let mut out = [0.0; 3];
        for i in 0..3 {
            out[i] = if self.last_t > 0.0 && span > 0.0 && ticks[i] >= self.last_ticks[i] {
                100.0 * (ticks[i] - self.last_ticks[i]) as f64 / hz / span
            } else {
                0.0
            };
            self.last_ticks[i] = ticks[i];
        }
        self.last_t = t;
        out
    }

    pub fn send(&mut self, gpu_pid: Option<u32>) {
        let (mut total_kb, mut avail_kb) = (0i64, 0i64);
        if let Ok(s) = std::fs::read_to_string("/proc/meminfo") {
            for line in s.lines() {
                let num = || line.split_whitespace().nth(1).and_then(|v| v.parse().ok()).unwrap_or(0);
                if line.starts_with("MemTotal:") {
                    total_kb = num();
                } else if line.starts_with("MemAvailable:") {
                    avail_kb = num();
                }
            }
        }
        let frames = self.elm.len();
        let gpu_ms = average(&mut self.gpu_ns, 1e-6);
        let elm_ms = average(&mut self.elm, 1000.0);
        let draw_ms = average(&mut self.draw, 1000.0);
        let [elm_cpu, host_cpu, gpu_cpu] = self.cpu_split(gpu_pid);
        // SAFETY: plain system call.
        let cores = unsafe { libc::sysconf(libc::_SC_NPROCESSORS_ONLN) };
        let round = |x: f64| (x * 10.0).round() / 10.0;
        let ms = |x: f64| (x * 1000.0).round() / 1000.0;
        let stats = ToElm::Stats {
            cores: cores as i64,
            cpu: round(self.cpu_load()),
            cpu_elm: round(elm_cpu),
            cpu_host: round(host_cpu),
            cpu_gpu: round(gpu_cpu),
            mem_used: (total_kb - avail_kb) / 1024,
            mem_total: total_kb / 1024,
            gpu_ms: ms(gpu_ms),
            elm_ms: ms(elm_ms),
            draw_ms: ms(draw_ms),
        };
        // For scripts/measure-frames.py: the stats on the serial console, without the
        // rest of ELMOS_DEBUG's logging, which would slow Elm down.
        if std::env::var_os("ELMOS_STATS").is_some() {
            // Just the fields, as JSON: {"stats": {...}} is the message.
            let json = serde_json::to_value(&stats).map(|v| v["stats"].to_string()).unwrap_or_default();
            log!("stats", "frames={} {}", frames, json);
        }
        elm::send(&stats);
    }
}

use crate::elm;
