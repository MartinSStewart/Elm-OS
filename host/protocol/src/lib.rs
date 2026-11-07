//! Every message between the Elm program and the host, in both directions, as Rust
//! types: `Effect` is what Elm asks for on its `toHost` port (elm/src/Effect.elm
//! encodes them), and `ToElm` is what the host sends on `fromHost` (Main.decodeInput,
//! Persist.elm and BootInfo.elm decode them). Both are JSON objects tagged by "t".
//!
//! Both sides are written by hand, so examples.json holds one example of every message,
//! and both sides are tested against it: `cargo test -p protocol` (the tests below)
//! checks the Rust side reads and writes exactly those, and elm/tests/ProtocolTest.elm
//! (make elm-tests) checks the Elm side does. Add a message here, to examples.json and
//! to the Elm side together; `make check` runs both tests.

use serde::{Deserialize, Serialize};

/// What Elm asks the host to do.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(tag = "t", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum Effect {
    /// 13 numbers per triangle: screen pixels, texture atlas pixels (see
    /// common/src/atlas.rs), and the colour as 0xRRGGBBAA, for each of the 3 corners
    /// x, y, u, v, then the colour.
    Render { tris: Vec<f64> },
    /// The mouse cursor's fill colour, 0xRRGGBBAA.
    Cursor { rgba: f64 },
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
    #[serde(default)]
    pub body: String,
    pub timeout_ms: Option<f64>,
}

/// What the host tells Elm: input, frames, hardware and network state, and the answers
/// to Elm's effects.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(tag = "t", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
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
    /// Where the data disk is mounted, or null without one.
    DataDisk { path: Option<String> },
    /// Any status, 404 included.
    HttpResponse { id: String, status: u16, body: String },
    HttpError { id: String, error: HttpFailure, message: String },
    /// Sorted; null if the directory can't be listed.
    Dir { path: String, entries: Option<Vec<String>> },
    /// Each path with its text, null if it can't be read.
    Files { id: String, files: Vec<(String, Option<String>)> },
    /// Hex, null unless all the bytes asked for were read.
    Bytes { path: String, offset: u64, hex: Option<String> },
    /// Hex, null if the file is shorter than asked or can't be read.
    Sha256 { path: String, hex: Option<String> },
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
    pub fn to_json(&self) -> String {
        serde_json::to_string(self).expect("a ToElm is always JSON")
    }
}

/// Reads one batch of Elm's effects (a JSON list). Effects that don't parse are
/// returned as errors in their place, so one bad effect doesn't lose the rest.
pub fn read_effects(json: &str) -> Result<Vec<Result<Effect, String>>, String> {
    let list: Vec<serde_json::Value> = serde_json::from_str(json).map_err(|e| e.to_string())?;
    Ok(list
        .into_iter()
        .map(|v| {
            let shown = v.to_string();
            serde_json::from_value(v).map_err(|e| format!("{e}: {shown:.200}"))
        })
        .collect())
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

    fn tag(v: &Value) -> String {
        v["t"].as_str().unwrap().to_owned()
    }

    /// Each kind of message once, so a new kind of message must get an example. (This
    /// match has no `_` arm, so it stops compiling until the new one is listed.)
    fn effect_tag(e: &Effect) -> &'static str {
        match e {
            Effect::Render { .. } => "render",
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
        }
    }
    const EFFECT_TAGS: usize = 15;

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
        }
    }
    const TO_ELM_TAGS: usize = 22;

    #[test]
    fn reads_every_effect_elm_sends() {
        let mut tags = std::collections::BTreeSet::new();
        for example in examples("toHost") {
            let effect: Effect = serde_json::from_value(example.clone())
                .unwrap_or_else(|e| panic!("can't read {example}: {e}"));
            assert_eq!(effect_tag(&effect), tag(&example));
            // Nothing in the example was ignored: it comes back the same.
            let back = serde_json::to_value(&effect).unwrap();
            assert!(same(&back, &example), "{example} came back as {back}");
            tags.insert(tag(&example));
        }
        assert_eq!(tags.len(), EFFECT_TAGS, "examples.json needs one toHost example of each Effect; it has {tags:?}");
    }

    #[test]
    fn sends_what_elm_reads() {
        let mut tags = std::collections::BTreeSet::new();
        for example in examples("fromHost") {
            let message: ToElm = serde_json::from_value(example.clone())
                .unwrap_or_else(|e| panic!("{example} isn't a ToElm: {e}"));
            assert_eq!(to_elm_tag(&message), tag(&example));
            let sent: Value = serde_json::from_str(&message.to_json()).unwrap();
            assert!(same(&sent, &example), "{example} is sent as {sent}");
            tags.insert(tag(&example));
        }
        assert_eq!(tags.len(), TO_ELM_TAGS, "examples.json needs one fromHost example of each ToElm; it has {tags:?}");
    }

    #[test]
    fn one_bad_effect_keeps_the_rest() {
        let read = read_effects(r#"[{"t":"wifiScan"},{"t":"noSuchEffect"},{"t":"wifiDisconnect"}]"#).unwrap();
        assert_eq!(read.len(), 3);
        assert_eq!(read[0], Ok(Effect::WifiScan));
        assert!(read[1].is_err());
        assert_eq!(read[2], Ok(Effect::WifiDisconnect));
    }
}
