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
    /// 1 to sample the atlas bilinearly, 0 for the nearest pixel.
    pub linear: u32,
    /// Left, top, width and height of the atlas rectangle the triangle repeats, in
    /// atlas pixels: u, v outside it wrap round into it, so the triangle shows the
    /// rectangle tiled (a pattern). Width 0 for none: u, v are used as they are.
    pub tile: [u16; 4],
    /// 1 to sample the image texture (common/src/images.rs, `Effect::WriteImage`)
    /// instead of the atlas: then u, v and the tile are in its pixels, and its colour
    /// multiplies the triangle's.
    pub image: u32,
    /// 1 to clamp u, v into the tile rather than wrap them round (so a picture's edge
    /// pixels repeat outwards, and bilinear sampling doesn't blend in its neighbours).
    pub clamp: u32,
}

/// How many bytes each triangle takes in `Effect::Render`.
pub const RENDER_TRIANGLE_BYTES: usize = 60;

/// Reads the scene in `Effect::Render`: 60 bytes a triangle, all little-endian. First
/// the 12 numbers of its corners as 32-bit floats, then three unsigned 32-bit integers:
/// its colour; its tile's left (low 16 bits) and top (high 16 bits); and its tile's
/// width (bits 0-15), height (bits 16-28), whether u, v clamp into the tile rather than
/// wrap round (bit 29 set), whether it samples the image texture rather than the atlas
/// (bit 30 set), and whether it samples bilinearly (bit 31 set) or by the nearest pixel. None if the length isn't a whole number of triangles.
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
                let (at, size) = (u32::from_le_bytes(word(b, 13)), u32::from_le_bytes(word(b, 14)));
                t.tile = [at as u16, (at >> 16) as u16, size as u16, (size >> 16) as u16 & 0x1fff];
                t.linear = size >> 31;
                t.image = (size >> 30) & 1;
                t.clamp = (size >> 29) & 1;
                t
            })
            .collect(),
    )
}

/// What one display shows: triangles as `read_render` reads them, in that display's
/// own pixels (0, 0 is its top left corner). The triangles are a byte string, so eco
/// and the host copy them rather than look at each number.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Scene {
    /// `Display::id`.
    pub display: u32,
    #[serde(with = "serde_bytes")]
    pub triangles: Vec<u8>,
}

/// A screen the host draws on. Displays sit side by side in one space that the mouse
/// moves through (`ToElm::Mouse` is in it): `x`, `y` is where the display's top left
/// corner is in that space, in pixels.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Display {
    /// The DRM connector's id: the same for the same socket from one boot to the next.
    pub id: u32,
    /// The connector's name as Linux gives it, such as "eDP-1" or "HDMI-A-1".
    pub name: String,
    pub x: i32,
    pub y: i32,
    pub w: u32,
    pub h: u32,
    /// Its physical size in millimetres, 0 if the screen didn't say.
    pub width_mm: u32,
    pub height_mm: u32,
}

/// What Elm asks the host to do.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum Effect {
    /// The scene to draw on each display, once a frame (see `Scene`).
    Render(Vec<Scene>),
    /// The mouse cursor: its fill colour, 0xRRGGBBAA, the UI scale (1 or 2), which
    /// sets how far mouse motion moves it, and where its picture is in the texture
    /// atlas (Elm picks the shape, elm/src/Cursor.elm, and the picture for the scale).
    /// Sent with every frame; the host redraws the cursor only when it changes.
    Cursor { rgba: u32, scale: u32, image: CursorImage },
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
    /// Replaces a file on the data disk with these bytes, atomically. No answer.
    WriteFile {
        path: String,
        #[serde(with = "serde_bytes")]
        data: Vec<u8>,
    },
    /// A line for the serial console / log, from Elm.
    Log { text: String },
    /// The answer to `ToElm::Switching`: the snapshot is written (the effects before
    /// this one), so the host can stop this program and start the new one.
    SwitchReady,
    /// Answered with `ToElm::Snapshot`: the data disk's snapshot file, as it is.
    ReadSnapshot,
    /// Replaces the snapshot with `data` (the host frames it: length and CRC-32,
    /// elm/src/Persist.elm reads them), atomically, and then drops the messages up to
    /// number `seq` from the log, which the snapshot has in it.
    WriteSnapshot {
        #[serde(with = "serde_bytes")]
        data: Vec<u8>,
        seq: u64,
    },
    /// Sends the logged messages numbered after `after` that went to earlier programs
    /// (each with its number), then `ToElm::ReplayDone`.
    ReplayLog { after: u64 },
    /// Opens a WebSocket (ws:// or wss://) with these extra request headers, such as a
    /// cookie. Answered with `ToElm::WebSocketOpened`, then a `ToElm::WebSocketMessage`
    /// for each message, and last `ToElm::WebSocketClosed`, all with the same id.
    WebSocketOpen { id: String, url: String, headers: Vec<(String, String)> },
    /// A binary message on an open WebSocket.
    WebSocketSend {
        id: String,
        #[serde(with = "serde_bytes")]
        data: Vec<u8>,
    },
    /// Closes a WebSocket; `ToElm::WebSocketClosed` follows.
    WebSocketClose { id: String },
    /// Opens a TLS connection to `host`:`port` (certificate checked against the CAs
    /// compiled in, as for HTTPS), for protocols like IMAP that aren't HTTP. Answered
    /// with `ToElm::TlsOpened`, then a `ToElm::TlsData` for each chunk of bytes the
    /// server sends, and last `ToElm::TlsClosed`, all with the same id. The host only
    /// moves bytes: what they mean is up to Elm.
    TlsOpen { id: String, host: String, port: u16 },
    /// Bytes to send on an open TLS connection.
    TlsSend {
        id: String,
        #[serde(with = "serde_bytes")]
        data: Vec<u8>,
    },
    /// Closes a TLS connection; `ToElm::TlsClosed` follows.
    TlsClose { id: String },
    /// Writes RGBA pixels (4 bytes each, red first, not premultiplied) into the image
    /// texture (common/src/images.rs), `width` to a row, as many rows as `pixels` holds,
    /// with the top left one at left, top. What falls outside the texture is dropped.
    /// The texture starts transparent at every boot, so Elm writes its pictures again
    /// each time it starts. No answer.
    WriteImage {
        left: u32,
        top: u32,
        width: u32,
        #[serde(with = "serde_bytes")]
        pixels: Vec<u8>,
    },
    /// Compiles these sources into a new build of the Elm program and switches to it
    /// (host/init/src/build.rs): every module, each as its path under elm/src (such as
    /// "Code/Types.elm") and its text. Refused unless the Model's types are the running
    /// build's. Answered with `ToElm::Build`s as it goes.
    Build { modules: Vec<(String, String)> },
    /// Lists the computer's disks and what is on them (host/init/src/install.rs), for
    /// the Install app. Answered with `ToElm::Disks`.
    ListDisks,
    /// Installs Elm OS on `disk` (`DiskInfo::name`): in `target`, it makes an EFI system
    /// partition, an "Elm OS tools" and an "Elm OS data" partition, copies itself there
    /// and adds a UEFI boot entry. Everything else on the disk is left as it is.
    /// `layout` is the `DiskInfo::layout` the choice was made from: the host refuses if
    /// the disk has changed since. With `keep_data`, the data partition starts with a
    /// copy of this one's (the Model, its log, builds), otherwise empty. Answered with
    /// `ToElm::Install`s as it goes.
    Install { disk: String, layout: String, target: InstallTarget, keep_data: bool },
    /// Replaces the Elm OS installed on `disk` (`DiskInfo::installed`) with this one,
    /// keeping its data partition: rewrites its EFI system partition's kernel and its
    /// tools partition. Answered like `Install`.
    UpdateInstall { disk: String, layout: String },
    /// Leaves a build made on this computer (`ToElm::System`'s `build` is `local-...`)
    /// for the newest deployed build, which it otherwise stays away from so as not to
    /// drop the edits it was made from. The host downloads and switches to it as it
    /// does for updates; a failure comes back as a `ToElm::Build` that failed.
    FollowDeployed,
}

/// Where on a disk `Effect::Install` puts Elm OS.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum InstallTarget {
    /// The free space (a `Region` without a partition) that starts at this byte.
    Free { start: u64 },
    /// In place of this partition (`PartitionInfo::number`), erasing it.
    Partition { number: u32 },
    /// The whole disk, erasing everything on it.
    WholeDisk,
}

/// A disk, for the Install app.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DiskInfo {
    /// The kernel's name for it, such as "nvme0n1" or "sda".
    pub name: String,
    /// What the disk says it is, such as "Samsung SSD 970 EVO 1TB" (can be empty).
    pub model: String,
    pub bytes: u64,
    pub usb: bool,
    /// Elm OS runs from this disk (its data partition is mounted from it).
    pub booted: bool,
    /// Some partition on it is in use (mounted), so it can't be written to.
    pub busy: bool,
    /// Elm OS is installed on it (an "Elm OS" EFI, tools and data partition), so
    /// `Effect::UpdateInstall` can update it.
    pub installed: bool,
    /// A fingerprint of its partition table and size: `Effect::Install` passes it back.
    pub layout: String,
    pub table: DiskTable,
    /// The disk from start to end: partitions and the free space between them.
    pub regions: Vec<Region>,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum DiskTable {
    Gpt,
    /// The old (MBR) kind: Elm OS can only go on the whole disk.
    Mbr,
    /// No partition table: an empty disk.
    Empty,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Region {
    /// Its first byte and size. Free space smaller than a megabyte isn't listed.
    pub start: u64,
    pub bytes: u64,
    /// None for free space.
    pub partition: Option<PartitionInfo>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PartitionInfo {
    pub number: u32,
    /// Its GPT name (can be empty).
    pub name: String,
    pub contents: Contents,
}

/// What a partition holds, from its type and the first bytes of it.
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum Contents {
    /// An EFI system partition: boot loaders (Windows', GRUB...). Never erased.
    EfiSystem,
    /// Windows' files (or another NTFS volume).
    Ntfs,
    /// Encrypted by Windows' BitLocker.
    BitLocker,
    /// Linux's usual file system (Mint, Ubuntu...).
    Ext4,
    Btrfs,
    Fat,
    Swap,
    /// Encrypted Linux (LUKS).
    Luks,
    /// Windows' small reserved partition.
    MicrosoftReserved,
    WindowsRecovery,
    ElmOsData,
    ElmOsTools,
    /// Only zeros at its start.
    Empty,
    Other,
}

/// How `Effect::Install` (or `UpdateInstall`) is going.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum InstallStatus {
    /// The step it is on, and how far through the whole install it is (0 to 1).
    Running { step: String, done: f64 },
    /// It stopped: at which step, and why. `wrote` says whether the disk was changed.
    Failed { step: String, message: String, wrote: bool },
    /// Done. `grub` is a GRUB menu entry that starts it, for a computer whose other
    /// system's GRUB comes first (Linux Mint's /etc/grub.d/40_custom).
    Installed { grub: String },
}

/// A mouse cursor's picture, `width` x `height` device pixels of the texture atlas: the
/// fill colour where the rectangle with its top left corner at `fill` (x, y in atlas
/// pixels) is covered, over black where the one at `outline` is. The hot spot (`hot_x`,
/// `hot_y`) is the pixel that points, which goes where the mouse is.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CursorImage {
    pub width: u32,
    pub height: u32,
    pub hot_x: u32,
    pub hot_y: u32,
    pub fill: [u32; 2],
    pub outline: Option<[u32; 2]>,
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
    /// First, to each program: the connected displays, the built-in one (if any)
    /// first. When they change later, `DisplaysChanged` says so.
    Displays { displays: Vec<Display> },
    /// Draw a frame now. `time` is the host's monotonic clock, in milliseconds (for
    /// how long since the last frame); `posix` is the wall clock, in whole milliseconds
    /// since 1970 (it can jump when NTP sets the clock).
    Frame { time: f64, posix: f64 },
    Mouse { x: i32, y: i32 },
    Button { b: i32, down: bool },
    /// Wheel clicks, positive is up.
    Wheel { dy: i32 },
    /// A key went down or up (evdev's code); `repeat` is the keyboard's autorepeat.
    Key { code: u16, down: bool, repeat: bool },
    /// Which renderer draws.
    Renderer { gpu: bool, name: String, hardware_cursor: bool },
    /// For the about page. `build` is the build running (programs on the data disk):
    /// "" for the built-in one, the commit's first 12 digits for a deployed one, or
    /// "local-..." for one made on this computer. Each program is told its own.
    System { kernel: String, cpu: String, commit: String, build: String },
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
        /// The ids of the WebSockets open now: they belong to the host and stay open
        /// from one program to the next. Any other is closed.
        web_sockets_open: Vec<String>,
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
    /// Once a second, so the program's clock-driven work is in the log too. `time` is
    /// the wall clock (CLOCK_REALTIME), in whole milliseconds since 1970 UTC: from the
    /// hardware clock at boot, then from the network (host/init/src/ntp.rs).
    Tick { time: f64 },
    /// The answer to `Effect::ReadSnapshot`: the snapshot file's bytes, as they are,
    /// null if there is none.
    Snapshot {
        #[serde(with = "serde_bytes")]
        data: Option<Vec<u8>>,
    },
    /// After `Effect::ReplayLog`'s messages: the number of the last message that went
    /// to an earlier program. Messages numbered after it are new.
    ReplayDone { upto: u64 },
    /// The WebSocket is open: the server's response headers (a cookie it sets, say).
    WebSocketOpened { id: String, headers: Vec<(String, String)> },
    /// A message from the server, binary or text (as UTF-8).
    WebSocketMessage {
        id: String,
        #[serde(with = "serde_bytes")]
        data: Vec<u8>,
    },
    /// The WebSocket has closed, or couldn't open, and why. Its id can be used again.
    WebSocketClosed { id: String, reason: String },
    /// A display was plugged in or out (or a window resized, in the dev runner): the
    /// displays now, as in `Displays`. Unlike `Displays`, not the start of a program.
    DisplaysChanged { displays: Vec<Display> },
    /// Smooth scrolling (two fingers on a touchpad), in UI pixels: how far the content
    /// under the pointer follows the fingers. Positive is down, the way the content
    /// goes for a `Wheel` click up. A mouse wheel still sends `Wheel`. No longer sent
    /// (see `Gesture`), but the message log still holds some.
    Scroll { dy: f64 },
    /// The fingers left the touchpad (or all but one did) while scrolling: the content
    /// they were scrolling should keep going at `velocity` UI pixels a second (positive
    /// is down, as for `Scroll`), slowing down. 0 when the fingers had stopped. Also
    /// sent with 0 when a finger touches the pad again, which stops any glide.
    ScrollMomentum { velocity: f64 },
    /// The TLS connection is open.
    TlsOpened { id: String },
    /// Bytes from the server, as they came: a chunk can end anywhere.
    TlsData {
        id: String,
        #[serde(with = "serde_bytes")]
        data: Vec<u8>,
    },
    /// The TLS connection has closed, or couldn't open, and why. Its id can be used again.
    TlsClosed { id: String, reason: String },
    /// How the build that `Effect::Build` asked for is going.
    Build { status: BuildStatus },
    /// Two fingers on a touchpad, in UI pixels: how far the content
    /// under the pointer follows the fingers. `dy` positive is down, the way the content
    /// goes for a `Wheel` click up; `dx` positive is right. `pinch` is how much the
    /// fingers spread: the distance between them now over what it was (1 when they
    /// kept their distance, above 1 zooms in). A report is either a scroll or a pinch,
    /// whichever the fingers did most. A mouse wheel still sends `Wheel`.
    Gesture { dx: f64, dy: f64, pinch: f64 },
    /// The computer's disks (`Effect::ListDisks`).
    Disks { disks: Vec<DiskInfo> },
    /// How `Effect::Install` or `UpdateInstall` is going.
    Install { status: InstallStatus },
}

/// A build made on the computer (`Effect::Build`): the step it is on, why it stopped
/// (the step and what the tools said), or that it worked and the host is switching to
/// it, which `ToElm::Switching` follows.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum BuildStatus {
    Running { step: String },
    Failed { step: String, output: String },
    Built { build: String },
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

/// The wall clock now, in whole milliseconds since 1970.
pub fn wall_clock_ms() -> f64 {
    let since_1970 = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH);
    since_1970.map_or(0, |d| d.as_millis()) as f64
}

impl ToElm {
    /// A `Tick` with the wall clock now.
    pub fn tick_now() -> ToElm {
        ToElm::Tick { time: wall_clock_ms() }
    }

    /// A `Frame` asked for at `time` on the host's monotonic clock, with the wall clock now.
    pub fn frame_now(time: f64) -> ToElm {
        ToElm::Frame { time, posix: wall_clock_ms() }
    }

    /// What goes on the socket to the Elm program.
    pub fn to_bytes(&self) -> Vec<u8> {
        postcard::to_allocvec(self).expect("a ToElm always encodes")
    }

    /// Reads what `to_bytes` wrote (a message in the log, persist.rs).
    pub fn from_bytes(bytes: &[u8]) -> Option<ToElm> {
        postcard::from_bytes(bytes).ok()
    }
}

/// Reads one message from Elm: its effects, in order. If it can't, the error says which
/// effect it couldn't read (its place in the list and its variant number), at which
/// byte, and shows the bytes from there, so a log line is enough to find the encoder
/// in elm/src/Effect.elm that disagrees with `Effect`.
pub fn read_effects(bytes: &[u8]) -> Result<Vec<Effect>, String> {
    let (count, mut rest) = postcard::take_from_bytes::<u32>(bytes).map_err(|e| format!("{e}, in the effect count"))?;
    let mut effects = Vec::with_capacity(count.min(1024) as usize);
    for i in 0..count {
        match postcard::take_from_bytes::<Effect>(rest) {
            Ok((effect, after)) => {
                effects.push(effect);
                rest = after;
            }
            Err(e) => {
                let at = bytes.len() - rest.len();
                let variant = postcard::take_from_bytes::<u32>(rest).map_or("?".to_owned(), |(v, _)| v.to_string());
                let shown: Vec<String> = rest.iter().take(48).map(|b| format!("{b:02x}")).collect();
                let read: Vec<&str> = effects.iter().map(effect_name).collect();
                return Err(format!(
                    "{e}, in effect {} of {count} (variant {variant}), at byte {at} of {}; after [{}]; bytes from there: {}",
                    i + 1,
                    bytes.len(),
                    read.join(", "),
                    shown.join(" ")
                ));
            }
        }
    }
    Ok(effects)
}

/// The effect's variant name, for logs.
pub fn effect_name(effect: &Effect) -> &'static str {
    match effect {
        Effect::Render(_) => "Render",
        Effect::Cursor { .. } => "Cursor",
        Effect::WifiScan => "WifiScan",
        Effect::WifiConnect { .. } => "WifiConnect",
        Effect::WifiDisconnect => "WifiDisconnect",
        Effect::Power { .. } => "Power",
        Effect::Http(_) => "Http",
        Effect::ListDir { .. } => "ListDir",
        Effect::ReadFiles { .. } => "ReadFiles",
        Effect::ReadBytes { .. } => "ReadBytes",
        Effect::Sha256 { .. } => "Sha256",
        Effect::WriteSys { .. } => "WriteSys",
        Effect::AppendFile { .. } => "AppendFile",
        Effect::WriteFile { .. } => "WriteFile",
        Effect::Log { .. } => "Log",
        Effect::SwitchReady => "SwitchReady",
        Effect::ReadSnapshot => "ReadSnapshot",
        Effect::WriteSnapshot { .. } => "WriteSnapshot",
        Effect::ReplayLog { .. } => "ReplayLog",
        Effect::WebSocketOpen { .. } => "WebSocketOpen",
        Effect::WebSocketSend { .. } => "WebSocketSend",
        Effect::WebSocketClose { .. } => "WebSocketClose",
        Effect::TlsOpen { .. } => "TlsOpen",
        Effect::TlsSend { .. } => "TlsSend",
        Effect::TlsClose { .. } => "TlsClose",
        Effect::WriteImage { .. } => "WriteImage",
        Effect::Build { .. } => "Build",
        Effect::ListDisks => "ListDisks",
        Effect::Install { .. } => "Install",
        Effect::UpdateInstall { .. } => "UpdateInstall",
        Effect::FollowDeployed => "FollowDeployed",
    }
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
            Effect::WebSocketOpen { .. } => "webSocketOpen",
            Effect::WebSocketSend { .. } => "webSocketSend",
            Effect::WebSocketClose { .. } => "webSocketClose",
            Effect::TlsOpen { .. } => "tlsOpen",
            Effect::TlsSend { .. } => "tlsSend",
            Effect::TlsClose { .. } => "tlsClose",
            Effect::WriteImage { .. } => "writeImage",
            Effect::Build { .. } => "build",
            Effect::ListDisks => "listDisks",
            Effect::Install { .. } => "install",
            Effect::UpdateInstall { .. } => "updateInstall",
            Effect::FollowDeployed => "followDeployed",
        }
    }
    const EFFECT_TAGS: usize = 31;

    fn to_elm_tag(m: &ToElm) -> &'static str {
        match m {
            ToElm::Displays { .. } => "displays",
            ToElm::Frame { .. } => "frame",
            ToElm::Mouse { .. } => "mouse",
            ToElm::Button { .. } => "button",
            ToElm::Wheel { .. } => "wheel",
            ToElm::Scroll { .. } => "scroll",
            ToElm::Gesture { .. } => "gesture",
            ToElm::ScrollMomentum { .. } => "scrollMomentum",
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
            ToElm::Tick { .. } => "tick",
            ToElm::Snapshot { .. } => "snapshot",
            ToElm::ReplayDone { .. } => "replayDone",
            ToElm::WebSocketOpened { .. } => "webSocketOpened",
            ToElm::WebSocketMessage { .. } => "webSocketMessage",
            ToElm::WebSocketClosed { .. } => "webSocketClosed",
            ToElm::DisplaysChanged { .. } => "displaysChanged",
            ToElm::TlsOpened { .. } => "tlsOpened",
            ToElm::TlsData { .. } => "tlsData",
            ToElm::TlsClosed { .. } => "tlsClosed",
            ToElm::Build { .. } => "build",
            ToElm::Disks { .. } => "disks",
            ToElm::Install { .. } => "install",
        }
    }
    const TO_ELM_TAGS: usize = 40;

    #[test]
    fn reads_the_render_example() {
        let render = examples("toHost").into_iter().find(|e| tag(e) == "render").unwrap();
        let Effect::Render(scenes) = serde_json::from_value(render).unwrap() else { panic!("not a Render") };
        assert_eq!(scenes.iter().map(|s| s.display).collect::<Vec<_>>(), vec![33, 34]);
        assert_eq!(read_render(&scenes[1].triangles), Some(vec![]));
        let bytes = &scenes[0].triangles;
        let at = |x: f32, y: f32| [x, y, 4.0 + x, 3588.0 + y];
        let tri = |corners| RenderTriangle { corners, rgba: 0xffff_ffff, linear: 0, tile: [0; 4], image: 0, clamp: 0 };
        let (tl, tr, br, bl) = (at(0.0, 0.0), at(10.0, 0.0), at(10.0, 10.0), at(0.0, 10.0));
        assert_eq!(read_render(bytes), Some(vec![tri([tl, tr, br]), tri([tl, br, bl])]));
        assert_eq!(read_render(&bytes[1..]), None);
    }

    #[test]
    fn reads_a_tile_and_linear_sampling() {
        // As Sprite.encoder packs them: left + top * 2^16, width + height * 2^16 + 2^31.
        let mut bytes = vec![0u8; 52];
        bytes.extend((256u32 + 224 * 65536).to_le_bytes());
        bytes.extend((16u32 + 20 * 65536 + (1 << 31)).to_le_bytes());
        let t = read_render(&bytes).unwrap()[0];
        assert_eq!((t.tile, t.linear), ([256, 224, 16, 20], 1));
        // Bit 30: the image texture.
        let mut bytes = vec![0u8; 52];
        bytes.extend((3u32 + 4 * 65536).to_le_bytes());
        bytes.extend((600u32 + 400 * 65536 + (1 << 30) + (1 << 29)).to_le_bytes());
        let t = read_render(&bytes).unwrap()[0];
        assert_eq!((t.tile, t.linear, t.image, t.clamp), ([3, 4, 600, 400], 0, 1, 1));
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
        // Variant 1 (Cursor), rgba 0xff0000ff as a varint, scale 2, then a 1 x 2
        // image with its hot spot at 0, 1, its fill at 5, 3600 and Some outline at
        // 300, 3601.
        let image = CursorImage { width: 1, height: 2, hot_x: 0, hot_y: 1, fill: [5, 3600], outline: Some([300, 3601]) };
        let cursor = Effect::Cursor { rgba: 0xff00_00ff, scale: 2, image };
        assert_eq!(write_effects(&[cursor]), vec![1, 1, 0xff, 0x81, 0x80, 0xf8, 0x0f, 2, 1, 2, 0, 1, 5, 0x90, 0x1c, 1, 0xac, 0x02, 0x91, 0x1c]);
        // Variant 2 (Mouse), zigzagged -1 and 300.
        assert_eq!(ToElm::Mouse { x: -1, y: 300 }.to_bytes(), vec![2, 1, 0xd8, 0x04]);
        assert!(read_effects(&[1, 99]).is_err());
        // The error says which effect couldn't be read, and shows its bytes.
        let bad = [2, 2, 3, 5, 0xff, 0xff];
        assert_eq!(
            read_effects(&bad),
            Err("Hit the end of buffer, expected more data, in effect 2 of 2 (variant 3), at byte 2 of 6; after [WifiScan]; bytes from there: 03 05 ff ff".to_owned())
        );
    }

    #[test]
    fn messages_carry_their_number() {
        let tick = ToElm::Tick { time: 0.0 }.to_bytes();
        assert_eq!(from_host_payload(None, &tick), [vec![0], tick.clone()].concat());
        assert_eq!(from_host_payload(Some(300), &tick), [vec![1, 0xac, 0x02], tick.clone()].concat());
        assert_eq!(read_from_host_payload(&from_host_payload(Some(300), &tick)), Some((Some(300), &tick[..])));
        assert_eq!(read_from_host_payload(&from_host_payload(None, &tick)), Some((None, &tick[..])));
    }
}
