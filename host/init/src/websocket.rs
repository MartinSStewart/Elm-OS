//! WebSockets for Elm (ws:// and wss://), each on a thread of its own, with tungstenite
//! for the protocol and rustls for TLS (the same as http.rs: ring for the crypto and
//! Mozilla's CA list compiled in, so no OpenSSL and no certificate files).
//!
//!   Effect::WebSocketOpen { id, url, headers }
//!   -> ToElm::WebSocketOpened { id, headers }   the server's response headers
//!   -> ToElm::WebSocketMessage { id, data }     each message, as bytes (text as UTF-8)
//!   -> ToElm::WebSocketClosed { id, reason }    once, at the end, failed opens included
//!   Effect::WebSocketSend { id, data }          a binary message
//!   Effect::WebSocketClose { id }
//!
//! A socket belongs to the host, not to the Elm program: it stays open while the host
//! switches programs, and each new program is told which are open (ToElm::DataDisk).
//! Elm does everything else, such as what the messages mean and reconnecting.

use std::collections::HashMap;
use std::io::{ErrorKind, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::sync::mpsc::{self, Receiver, Sender, TryRecvError};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use protocol::ToElm;
use tungstenite::client::IntoClientRequest;
use tungstenite::handshake::client::Response;
use tungstenite::{Message, WebSocket};

use crate::elm;

/// How long to wait for the server to accept the connection.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
/// How often the socket's thread looks for messages from Elm to send, while waiting
/// for the server.
const POLL: Duration = Duration::from_millis(10);
/// Messages bigger than this close the socket rather than fill the memory.
const MAX_MESSAGE: usize = 64 << 20;

enum Command {
    Send(Vec<u8>),
    Close,
}

fn sockets() -> &'static Mutex<HashMap<String, Sender<Command>>> {
    static SOCKETS: OnceLock<Mutex<HashMap<String, Sender<Command>>>> = OnceLock::new();
    SOCKETS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn lock() -> std::sync::MutexGuard<'static, HashMap<String, Sender<Command>>> {
    sockets().lock().unwrap_or_else(|e| e.into_inner())
}

/// The ids of the sockets open now (or opening), sorted.
pub fn open_ids() -> Vec<String> {
    let mut ids: Vec<String> = lock().keys().cloned().collect();
    ids.sort();
    ids
}

pub fn open(id: String, url: String, headers: Vec<(String, String)>) {
    let (tx, rx) = mpsc::channel();
    {
        let mut s = lock();
        if s.contains_key(&id) {
            log!("websocket", "{id} is open already");
            return;
        }
        s.insert(id.clone(), tx);
    }
    let spawned = std::thread::Builder::new().name("websocket".into()).spawn({
        let id = id.clone();
        move || {
            let reason = match connect(&url, &headers) {
                Ok((socket, response)) => {
                    log!("websocket", "{id}: connected to {url}");
                    let headers = response
                        .headers()
                        .iter()
                        .map(|(k, v)| (k.as_str().to_owned(), String::from_utf8_lossy(v.as_bytes()).into_owned()))
                        .collect();
                    elm::send(&ToElm::WebSocketOpened { id: id.clone(), headers });
                    run(&id, socket, rx)
                }
                Err(e) => e,
            };
            log!("websocket", "{id}: closed ({reason})");
            lock().remove(&id);
            elm::send(&ToElm::WebSocketClosed { id, reason });
        }
    });
    if spawned.is_err() {
        lock().remove(&id);
        elm::send(&ToElm::WebSocketClosed { id, reason: "couldn't start a thread".into() });
    }
}

pub fn send(id: &str, data: Vec<u8>) {
    match lock().get(id) {
        Some(tx) => {
            let _ = tx.send(Command::Send(data));
        }
        None => log!("websocket", "sending on {id}, which isn't open"),
    }
}

pub fn close(id: &str) {
    if let Some(tx) = lock().get(id) {
        let _ = tx.send(Command::Close);
    }
}

/// TLS or not, the socket's stream.
pub enum Stream {
    Plain(TcpStream),
    Tls(Box<rustls::StreamOwned<rustls::ClientConnection, TcpStream>>),
}

impl Stream {
    pub fn tcp(&self) -> &TcpStream {
        match self {
            Stream::Plain(s) => s,
            Stream::Tls(s) => &s.sock,
        }
    }
}

impl Read for Stream {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        match self {
            Stream::Plain(s) => s.read(buf),
            Stream::Tls(s) => s.read(buf),
        }
    }
}

impl Write for Stream {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        match self {
            Stream::Plain(s) => s.write(buf),
            Stream::Tls(s) => s.write(buf),
        }
    }
    fn flush(&mut self) -> std::io::Result<()> {
        match self {
            Stream::Plain(s) => s.flush(),
            Stream::Tls(s) => s.flush(),
        }
    }
}

pub fn tls_config() -> Arc<rustls::ClientConfig> {
    static CONFIG: OnceLock<Arc<rustls::ClientConfig>> = OnceLock::new();
    CONFIG
        .get_or_init(|| {
            let roots = rustls::RootCertStore { roots: webpki_roots::TLS_SERVER_ROOTS.to_vec() };
            let config = rustls::ClientConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
                .with_safe_default_protocol_versions()
                .expect("ring supports the default TLS versions")
                .with_root_certificates(roots)
                .with_no_client_auth();
            Arc::new(config)
        })
        .clone()
}

fn connect(url: &str, headers: &[(String, String)]) -> Result<(WebSocket<Stream>, Response), String> {
    let mut request = url.into_client_request().map_err(|e| format!("bad url: {e}"))?;
    for (name, value) in headers {
        let name = tungstenite::http::HeaderName::from_bytes(name.as_bytes()).map_err(|e| format!("bad header: {e}"))?;
        let value = tungstenite::http::HeaderValue::from_str(value).map_err(|e| format!("bad header: {e}"))?;
        request.headers_mut().append(name, value);
    }
    let uri = request.uri().clone();
    let tls = match uri.scheme_str() {
        Some("wss") => true,
        Some("ws") => false,
        _ => return Err("the url must start with ws:// or wss://".into()),
    };
    let host = uri.host().ok_or("the url has no host")?.to_owned();
    let port = uri.port_u16().unwrap_or(if tls { 443 } else { 80 });
    let address = (host.as_str(), port)
        .to_socket_addrs()
        .map_err(|e| format!("can't find {host}: {e}"))?
        .next()
        .ok_or_else(|| format!("can't find {host}"))?;
    let tcp = TcpStream::connect_timeout(&address, CONNECT_TIMEOUT).map_err(|e| format!("can't connect: {e}"))?;
    tcp.set_read_timeout(Some(CONNECT_TIMEOUT)).map_err(|e| e.to_string())?;
    tcp.set_write_timeout(Some(CONNECT_TIMEOUT)).map_err(|e| e.to_string())?;
    tcp.set_nodelay(true).ok();
    let stream = if tls {
        let name = rustls::pki_types::ServerName::try_from(host.clone()).map_err(|e| format!("bad host: {e}"))?;
        let connection = rustls::ClientConnection::new(tls_config(), name).map_err(|e| format!("TLS: {e}"))?;
        Stream::Tls(Box::new(rustls::StreamOwned::new(connection, tcp)))
    } else {
        Stream::Plain(tcp)
    };
    let config = tungstenite::protocol::WebSocketConfig::default()
        .max_message_size(Some(MAX_MESSAGE))
        .max_frame_size(Some(MAX_MESSAGE));
    let (socket, response) = tungstenite::client::client_with_config(request, stream, Some(config))
        .map_err(|e| format!("handshake: {e}"))?;
    socket.get_ref().tcp().set_read_timeout(Some(POLL)).map_err(|e| e.to_string())?;
    Ok((socket, response))
}

fn waiting(e: &tungstenite::Error) -> bool {
    matches!(e, tungstenite::Error::Io(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut))
}

/// Sends what Elm asks and reads what the server sends, until one side closes. Returns
/// why it closed.
fn run(id: &str, mut socket: WebSocket<Stream>, commands: Receiver<Command>) -> String {
    loop {
        loop {
            match commands.try_recv() {
                Ok(Command::Send(data)) => {
                    if let Err(e) = socket.send(Message::binary(data)) {
                        if !waiting(&e) {
                            return format!("sending: {e}");
                        }
                    }
                }
                Ok(Command::Close) | Err(TryRecvError::Disconnected) => {
                    let _ = socket.close(None);
                    let _ = socket.flush();
                    return "closed by Elm".into();
                }
                Err(TryRecvError::Empty) => break,
            }
        }
        match socket.read() {
            Ok(Message::Binary(data)) => elm::send(&ToElm::WebSocketMessage { id: id.to_owned(), data: data.to_vec() }),
            Ok(Message::Text(text)) => {
                elm::send(&ToElm::WebSocketMessage { id: id.to_owned(), data: text.as_bytes().to_vec() })
            }
            Ok(Message::Close(frame)) => {
                return match frame {
                    Some(f) => format!("closed by the server: {} {}", u16::from(f.code), f.reason),
                    None => "closed by the server".into(),
                }
            }
            Ok(Message::Ping(_) | Message::Pong(_) | Message::Frame(_)) => {}
            Err(e) if waiting(&e) => {
                // A pong to the server's ping may be waiting to go.
                if let Err(e) = socket.flush() {
                    if !waiting(&e) {
                        return format!("sending: {e}");
                    }
                }
            }
            Err(tungstenite::Error::ConnectionClosed) => return "closed".into(),
            Err(e) => return e.to_string(),
        }
    }
}
