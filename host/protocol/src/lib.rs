//! Every message between the Elm program and the host, in both directions, as Rust
//! types: `Effect` is what Elm asks for on its `toHost` port (elm/src/Effect.elm
//! encodes them), and `ToElm` is what the host sends on `fromHost`
//! (elm/src/HostMessage.elm decodes them).
//!
//! On the wire both are postcard (https://postcard.jamesmunns.com/wire-format): compact
//! binary, with no field names. A message from Elm is a `Vec<Effect>`; one from the host
//! is one `ToElm`. In short: an enum is its variant's number (counting from 0 in the
//! order below) and then its fields in order; unsigned integers are varints (7 bits a
//! byte, low first, the top bit set on all but the last byte); signed ones are
//! zigzagged first (0, -1, 1, -2 ... become 0, 1, 2, 3 ...); f64 is 8 bytes and f32 4,
//! little-endian; bool is a byte; Option is a byte (0 None, 1 Some) and the value;
//! strings, byte strings and lists are their length as a varint, then the contents.
//! So the order of variants and of fields is the format: Elm's codecs follow it.
//!
//! Both sides are written by hand, so examples.json holds one example of every message
//! (as JSON, to be readable), and both sides are tested against it: `cargo test -p
//! protocol` (the tests below) checks the Rust side reads and writes exactly those, and
//! elm/tests/ProtocolTest.elm (make elm-tests) checks that the Elm side's bytes are the
//! same as Rust's (`cargo run -p protocol --bin protocol-examples` prints them). Add a
//! message here, to examples.json and to the Elm side together; `make check` runs both
//! tests.

use serde::{Deserialize, Serialize};

pub mod link;

/// A triangle of the scene Elm draws: x, y, u, v of each corner (screen pixels, then
/// texture atlas pixels: see common/src/atlas.rs) and the colour, 0xRRGGBBAA.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct RenderTriangle {
    pub corners: [[f32; 4]; 3],
    pub rgba: u32,
}

/// How many bytes each triangle takes in `Effect::Render`.
pub const RENDER_TRIANGLE_BYTES: usize = 52;

/// Reads the scene in `Effect::Render`: 52 bytes a triangle, the 12 numbers of its
/// corners as 32-bit floats and then its colour as an unsigned 32-bit integer, all
/// little-endian. None if the length isn't a whole number of triangles.
pub fn read_render(bytes: &[u8]) -> Option<Vec<RenderTriangle>> {
    if bytes.len() % RENDER_TRIANGLE_BYTES != 0 {
        return None;
    }
    let word = |b: &[u8], i: usize| [b[4 * i], b[4 * i + 1], b[4 * i + 2], b[4 * i + 3]];
    Some(
        bytes
            .chunks_exact(RENDER_TRIANGLE_BYTES)
            .map(|b| {
                let mut t = RenderTriangle::default();
                for k in 0..12 {
                    t.corners[k / 4][k % 4] = f32::from_le_bytes(word(b, k));
                }
                t.rgba = u32::from_le_bytes(word(b, 12));
                t
            })
            .collect(),
    )
}

/// What Elm asks the host to do.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum Effect {
    /// The scene to draw, once a frame: triangles as `read_render` reads them. A byte
    /// string, so eco and the host copy it rather than look at each number.
    Render(#[serde(with = "serde_bytes")] Vec<u8>),
    /// The mouse cursor's fill colour, 0xRRGGBBAA, and the UI scale (1 or 2), which
    /// sets the cursor's size and how far mouse motion moves it.
    Cursor { rgba: u32, scale: u32 },
    WifiScan,
    WifiConnect { ssid: String, password: String },
    WifiDisconnect,
    Power { action: PowerAction },
    /// Answered with `ToElm::HttpResponse` or `ToElm::HttpError`, with the same id.
    Http(HttpRequest),
    /// Answered with `ToElm::Dir`.
    ListDir { path: String },
    /// Answered with `ToElm::Files`.
    ReadFiles { id: String, paths: Vec<String> },
    /// Answered with `ToElm::Bytes`.
    ReadBytes { path: String, offset: u64, length: usize },
    /// Answered with `ToElm::Sha256`: of the first `length` bytes, or the whole file.
    Sha256 { path: String, length: Option<u64> },
    /// Writes a kernel setting under /sys. No answer.
    WriteSys { path: String, text: String },
    /// Adds `text` to the end of a file on the data disk. No answer.
    AppendFile { path: String, text: String },
    /// Replaces a file on the data disk, atomically. No answer.
    WriteFile { path: String, text: String },
    /// A line for the serial console / log, from Elm.
    Log { text: String },
    /// The answer to `ToElm::Switching`: the snapshot is written (the effects before
    /// this one), so the host can stop this program and start the new one.
    SwitchReady,
    /// Answered with `ToElm::Snapshot`: the data disk's snapshot file, as it is.
    ReadSnapshot,
    /// Replaces the snapshot with `text` (the host frames it: length and CRC-32,
    /// elm/src/Persist.elm reads them), atomically, and then drops the messages up to
    /// number `seq` from the log, which the snapshot has in it.
    WriteSnapshot { text: String, seq: u64 },
    /// Sends the logged messages numbered after `after` that went to earlier programs
    /// (each with its number), then `ToElm::ReplayDone`.
    ReplayLog { after: u64 },
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum PowerAction {
    Off,
    Restart,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HttpRequest {
    pub id: String,
    pub method: String,
    pub url: String,
    #[serde(default)]
    pub headers: Vec<(String, String)>,
    /// Bytes, so any kind of body can be sent (an empty one for none).
    #[serde(default, with = "serde_bytes")]
    pub body: Vec<u8>,
    pub timeout_ms: Option<f64>,
}

/// What the host tells Elm: input, frames, hardware and network state, and the answers
/// to Elm's effects.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum ToElm {
    /// First, once: the screen's size in pixels.
    Screen { w: u32, h: u32 },
    /// Draw a frame now. The host's monotonic clock, in milliseconds.
    Frame { time: f64 },
    Mouse { x: i32, y: i32 },
    Button { b: i32, down: bool },
    /// Wheel clicks, positive is up.
    Wheel { dy: i32 },
    /// A key went down or up (evdev's code); `repeat` is the keyboard's autorepeat.
    Key { code: u16, down: bool, repeat: bool },
    /// Which renderer draws.
    Renderer { gpu: bool, name: String, hardware_cursor: bool },
    /// For the about page.
    System { kernel: String, cpu: String, commit: String },
    /// Once, when the first frame is on screen: milliseconds since the kernel started.
    Boot { init_ms: f64, elm_ms: f64, frame_ms: f64 },
    /// For the debug overlay, every second. -1 for a time the host doesn't know.
    Stats {
        cores: i64,
        cpu: f64,
        cpu_elm: f64,
        cpu_host: f64,
        cpu_gpu: f64,
        mem_used: i64,
        mem_total: i64,
        gpu_ms: f64,
        elm_ms: f64,
        draw_ms: f64,
    },
    /// The wifi card, if there is one.
    WifiDevice { name: Option<String> },
    WifiScan { networks: Vec<WifiNetwork> },
    WifiStatus { state: WifiState, ssid: String, ip: String, error: String },
    /// The wired (Ethernet) cards; empty without one.
    Wired { links: Vec<WiredLink> },
    /// Only when set on the kernel command line, for the tests.
    NetConfig { geo_url: String, weather_url: String },
    /// Where the data disk is mounted, or null without one. Sent again to each Elm
    /// program the host starts (elm.rs), with the ids of the HTTP requests an earlier
    /// one made that the host is still working on, or has an answer for that it will
    /// deliver next: those weren't cut off (Persist.elm).
    DataDisk {
        path: Option<String>,
        http_in_flight: Vec<String>,
    },
    /// Any status, 404 included. The body as it came, so not necessarily text.
    HttpResponse {
        id: String,
        status: u16,
        #[serde(with = "serde_bytes")]
        body: Vec<u8>,
    },
    HttpError { id: String, error: HttpFailure, message: String },
    /// Sorted; null if the directory can't be listed.
    Dir { path: String, entries: Option<Vec<String>> },
    /// Each path with its text, null if it can't be read.
    Files { id: String, files: Vec<(String, Option<String>)> },
    /// Hex, null unless all the bytes asked for were read.
    Bytes { path: String, offset: u64, hex: Option<String> },
    /// Hex, null if the file is shorter than asked or can't be read.
    Sha256 { path: String, hex: Option<String> },
    /// The host is about to replace this program with build `to` (elm.rs): take a
    /// snapshot and answer `Effect::SwitchReady`. After that answer, this program gets
    /// one more frame (to show it is upgrading) and nothing else.
    Switching { to: String },
    /// The newest deployed build (update.rs) is for another host version, so this
    /// computer can't switch to it: its USB stick needs flashing again. Sent again to
    /// each program the host starts.
    ReflashNeeded { build: String },
    /// Once a second, so the program's clock-driven work is in the log too.
    Tick,
    /// The answer to `Effect::ReadSnapshot`: the snapshot file's text, null if there
    /// is none.
    Snapshot { text: Option<String> },
    /// After `Effect::ReplayLog`'s messages: the number of the last message that went
    /// to an earlier program. Messages numbered after it are new.
    ReplayDone { upto: u64 },
}

/// Whether the host writes this message in the log (on the data disk) before sending
/// it, so that replaying the log gives back what the program did: every message but
/// the ones about the log itself.
pub fn is_logged(msg: &ToElm) -> bool {
    !matches!(msg, ToElm::DataDisk { .. } | ToElm::Snapshot { .. } | ToElm::ReplayDone { .. })
}

/// What goes on the socket to the Elm program for one message: its number in the log
/// (an Option<u64> in postcard: 0, or 1 and a varint), then the message
/// (`ToElm::to_bytes`).
pub fn from_host_payload(seq: Option<u64>, message: &[u8]) -> Vec<u8> {
    let mut out = postcard::to_allocvec(&seq).expect("an Option<u64> always encodes");
    out.extend_from_slice(message);
    out
}

/// The number and the message's bytes, from `from_host_payload`'s.
pub fn read_from_host_payload(payload: &[u8]) -> Option<(Option<u64>, &[u8])> {
    postcard::take_from_bytes::<Option<u64>>(payload).ok()
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct WifiNetwork {
    pub ssid: String,
    /// dBm
    pub signal: i32,
    pub security: Security,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum Security {
    Open,
    Wpa,
    /// WPA3 only, which our wpa_supplicant can't join (it has no SAE).
    Wpa3,
    Enterprise,
    Wep,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum WifiState {
    Idle,
    Connecting,
    Dhcp,
    Connected,
    Failed,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct WiredLink {
    pub name: String,
    pub state: WiredState,
    pub ip: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum WiredState {
    NoCable,
    Dhcp,
    Connected,
    Failed,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum HttpFailure {
    BadUrl,
    Timeout,
    Network,
}

impl ToElm {
    /// What goes on the socket to the Elm program.
    pub fn to_bytes(&self) -> Vec<u8> {
        postcard::to_allocvec(self).expect("a ToElm always encodes")
    }

    /// Reads what `to_bytes` wrote (a message in the log, persist.rs).
    pub fn from_bytes(bytes: &[u8]) -> Option<ToElm> {
        postcard::from_bytes(bytes).ok()
    }
}

/// Reads one message from Elm: its effects, in order.
pub fn read_effects(bytes: &[u8]) -> Result<Vec<Effect>, String> {
    postcard::from_bytes(bytes).map_err(|e| e.to_string())
}

/// What Elm sends for these effects (for the tests, and protocol-examples).
pub fn write_effects(effects: &[Effect]) -> Vec<u8> {
    postcard::to_allocvec(effects).expect("Effects always encode")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    fn examples(direction: &str) -> Vec<Value> {
        let all: Value = serde_json::from_str(include_str!("../examples.json")).unwrap();
        all[direction].as_array().unwrap().clone()
    }

    /// JSON values that mean the same: numbers compared as numbers (1 and 1.0 are the same).
    fn same(a: &Value, b: &Value) -> bool {
        match (a, b) {
            (Value::Number(x), Value::Number(y)) => x.as_f64() == y.as_f64(),
            (Value::Array(x), Value::Array(y)) => x.len() == y.len() && x.iter().zip(y).all(|(x, y)| same(x, y)),
            (Value::Object(x), Value::Object(y)) => {
                x.len() == y.len() && x.iter().all(|(k, v)| y.get(k).is_some_and(|w| same(v, w)))
            }
            _ => a == b,
        }
    }

    /// The variant's name: "name", or {"name": fields}.
    fn tag(v: &Value) -> String {
        match v {
            Value::String(t) => t.clone(),
            Value::Object(o) if o.len() == 1 => o.keys().next().unwrap().clone(),
            _ => panic!("{v} isn't an enum variant"),
        }
    }

    /// Each kind of message once, so a new kind of message must get an example. (This
    /// match has no `_` arm, so it stops compiling until the new one is listed.)
    fn effect_tag(e: &Effect) -> &'static str {
        match e {
            Effect::Render(_) => "render",
            Effect::Cursor { .. } => "cursor",
            Effect::WifiScan => "wifiScan",
            Effect::WifiConnect { .. } => "wifiConnect",
            Effect::WifiDisconnect => "wifiDisconnect",
            Effect::Power { .. } => "power",
            Effect::Http(_) => "http",
            Effect::ListDir { .. } => "listDir",
            Effect::ReadFiles { .. } => "readFiles",
            Effect::ReadBytes { .. } => "readBytes",
            Effect::Sha256 { .. } => "sha256",
            Effect::WriteSys { .. } => "writeSys",
            Effect::AppendFile { .. } => "appendFile",
            Effect::WriteFile { .. } => "writeFile",
            Effect::Log { .. } => "log",
            Effect::SwitchReady => "switchReady",
            Effect::ReadSnapshot => "readSnapshot",
            Effect::WriteSnapshot { .. } => "writeSnapshot",
            Effect::ReplayLog { .. } => "replayLog",
        }
    }
    const EFFECT_TAGS: usize = 19;

    fn to_elm_tag(m: &ToElm) -> &'static str {
        match m {
            ToElm::Screen { .. } => "screen",
            ToElm::Frame { .. } => "frame",
            ToElm::Mouse { .. } => "mouse",
            ToElm::Button { .. } => "button",
            ToElm::Wheel { .. } => "wheel",
            ToElm::Key { .. } => "key",
            ToElm::Renderer { .. } => "renderer",
            ToElm::System { .. } => "system",
            ToElm::Boot { .. } => "boot",
            ToElm::Stats { .. } => "stats",
            ToElm::WifiDevice { .. } => "wifiDevice",
            ToElm::WifiScan { .. } => "wifiScan",
            ToElm::WifiStatus { .. } => "wifiStatus",
            ToElm::Wired { .. } => "wired",
            ToElm::NetConfig { .. } => "netConfig",
            ToElm::DataDisk { .. } => "dataDisk",
            ToElm::HttpResponse { .. } => "httpResponse",
            ToElm::HttpError { .. } => "httpError",
            ToElm::Dir { .. } => "dir",
            ToElm::Files { .. } => "files",
            ToElm::Bytes { .. } => "bytes",
            ToElm::Sha256 { .. } => "sha256",
            ToElm::Switching { .. } => "switching",
            ToElm::ReflashNeeded { .. } => "reflashNeeded",
            ToElm::Tick => "tick",
            ToElm::Snapshot { .. } => "snapshot",
            ToElm::ReplayDone { .. } => "replayDone",
        }
    }
    const TO_ELM_TAGS: usize = 27;

    #[test]
    fn reads_the_render_example() {
        let render = examples("toHost").into_iter().find(|e| tag(e) == "render").unwrap();
        let Effect::Render(bytes) = serde_json::from_value(render).unwrap() else { panic!("not a Render") };
        let at = |x, y| [x, y, 252.0, 252.0];
        assert_eq!(
            read_render(&bytes),
            Some(vec![RenderTriangle { corners: [at(0.0, 0.0), at(10.0, 0.0), at(0.0, 10.0)], rgba: 0xffff_ffff }])
        );
        assert_eq!(read_render(&bytes[1..]), None);
    }

    #[test]
    fn reads_every_effect_elm_sends() {
        let mut tags = std::collections::BTreeSet::new();
        let mut all = Vec::new();
        for example in examples("toHost") {
            let effect: Effect = serde_json::from_value(example.clone())
                .unwrap_or_else(|e| panic!("can't read {example}: {e}"));
            assert_eq!(effect_tag(&effect), tag(&example));
            // Nothing in the example was ignored: it comes back the same.
            let back = serde_json::to_value(&effect).unwrap();
            assert!(same(&back, &example), "{example} came back as {back}");
            tags.insert(tag(&example));
            all.push(effect);
        }
        assert_eq!(tags.len(), EFFECT_TAGS, "examples.json needs one toHost example of each Effect; it has {tags:?}");
        // And on the wire, all of them in one message.
        assert_eq!(read_effects(&write_effects(&all)), Ok(all));
    }

    #[test]
    fn sends_what_elm_reads() {
        let mut tags = std::collections::BTreeSet::new();
        for example in examples("fromHost") {
            let message: ToElm = serde_json::from_value(example.clone())
                .unwrap_or_else(|e| panic!("{example} isn't a ToElm: {e}"));
            assert_eq!(to_elm_tag(&message), tag(&example));
            let back = serde_json::to_value(&message).unwrap();
            assert!(same(&back, &example), "{example} came back as {back}");
            assert_eq!(postcard::from_bytes::<ToElm>(&message.to_bytes()), Ok(message));
            tags.insert(tag(&example));
        }
        assert_eq!(tags.len(), TO_ELM_TAGS, "examples.json needs one fromHost example of each ToElm; it has {tags:?}");
    }

    #[test]
    fn the_wire_format_is_postcard() {
        // Variant 1 (Cursor), rgba 0xff0000ff as a varint, scale 2.
        let cursor = Effect::Cursor { rgba: 0xff00_00ff, scale: 2 };
        assert_eq!(write_effects(&[cursor]), vec![1, 1, 0xff, 0x81, 0x80, 0xf8, 0x0f, 2]);
        // Variant 2 (Mouse), zigzagged -1 and 300.
        assert_eq!(ToElm::Mouse { x: -1, y: 300 }.to_bytes(), vec![2, 1, 0xd8, 0x04]);
        assert!(read_effects(&[1, 99]).is_err());
    }

    #[test]
    fn messages_carry_their_number() {
        let tick = ToElm::Tick.to_bytes();
        assert_eq!(from_host_payload(None, &tick), [vec![0], tick.clone()].concat());
        assert_eq!(from_host_payload(Some(300), &tick), [vec![1, 0xac, 0x02], tick.clone()].concat());
        assert_eq!(read_from_host_payload(&from_host_payload(Some(300), &tick)), Some((Some(300), &tick[..])));
        assert_eq!(read_from_host_payload(&from_host_payload(None, &tick)), Some((None, &tick[..])));
    }
}
