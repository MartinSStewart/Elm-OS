//! TLS connections for Elm, for protocols that aren't HTTP (IMAP, for the email app),
//! each on a thread of its own. The TLS is the same as websocket.rs's (rustls with ring,
//! Mozilla's CA list compiled in). This only moves bytes: what they mean is Elm's.
//!
//!   Effect::TlsOpen { id, host, port }
//!   -> ToElm::TlsOpened { id }          the handshake is done, the certificate checked
//!   -> ToElm::TlsData { id, data }      bytes from the server, as they come
//!   -> ToElm::TlsClosed { id, reason }  once, at the end, failed opens included
//!   Effect::TlsSend { id, data }
//!   Effect::TlsClose { id }
//!
//! A connection belongs to the host, so it outlasts an Elm program that is replaced; the
//! email app gives each session a fresh id and closes the ones it gives up on.

use std::collections::HashMap;
use std::io::{ErrorKind, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::sync::mpsc::{self, Receiver, Sender, TryRecvError};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use protocol::ToElm;

use crate::elm;
use crate::websocket::{tls_config, Stream};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
/// How often a connection's thread looks for bytes from Elm to send, while waiting for
/// the server.
const POLL: Duration = Duration::from_millis(10);
const CHUNK: usize = 64 * 1024;

enum Command {
    Send(Vec<u8>),
    Close,
}

fn connections() -> &'static Mutex<HashMap<String, Sender<Command>>> {
    static CONNECTIONS: OnceLock<Mutex<HashMap<String, Sender<Command>>>> = OnceLock::new();
    CONNECTIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn lock() -> std::sync::MutexGuard<'static, HashMap<String, Sender<Command>>> {
    connections().lock().unwrap_or_else(|e| e.into_inner())
}

pub fn open(id: String, host: String, port: u16) {
    let (tx, rx) = mpsc::channel();
    {
        let mut c = lock();
        if c.contains_key(&id) {
            log!("tls", "{id} is open already");
            return;
        }
        c.insert(id.clone(), tx);
    }
    let spawned = std::thread::Builder::new().name("tls".into()).spawn({
        let id = id.clone();
        move || {
            let reason = match connect(&host, port) {
                Ok(stream) => {
                    log!("tls", "{id}: connected to {host}:{port}");
                    elm::send(&ToElm::TlsOpened { id: id.clone() });
                    run(&id, stream, rx)
                }
                Err(e) => e,
            };
            log!("tls", "{id}: closed ({reason})");
            lock().remove(&id);
            elm::send(&ToElm::TlsClosed { id, reason });
        }
    });
    if spawned.is_err() {
        lock().remove(&id);
        elm::send(&ToElm::TlsClosed { id, reason: "couldn't start a thread".into() });
    }
}

pub fn send(id: &str, data: Vec<u8>) {
    match lock().get(id) {
        Some(tx) => {
            let _ = tx.send(Command::Send(data));
        }
        None => log!("tls", "sending on {id}, which isn't open"),
    }
}

pub fn close(id: &str) {
    if let Some(tx) = lock().get(id) {
        let _ = tx.send(Command::Close);
    }
}

fn connect(host: &str, port: u16) -> Result<Stream, String> {
    let address = (host, port)
        .to_socket_addrs()
        .map_err(|e| format!("can't find {host}: {e}"))?
        .next()
        .ok_or_else(|| format!("can't find {host}"))?;
    let tcp = TcpStream::connect_timeout(&address, CONNECT_TIMEOUT).map_err(|e| format!("can't connect: {e}"))?;
    tcp.set_read_timeout(Some(CONNECT_TIMEOUT)).map_err(|e| e.to_string())?;
    tcp.set_write_timeout(Some(CONNECT_TIMEOUT)).map_err(|e| e.to_string())?;
    tcp.set_nodelay(true).ok();
    let name = rustls::pki_types::ServerName::try_from(host.to_owned()).map_err(|e| format!("bad host: {e}"))?;
    let connection = rustls::ClientConnection::new(tls_config(), name).map_err(|e| format!("TLS: {e}"))?;
    let mut stream = Stream::Tls(Box::new(rustls::StreamOwned::new(connection, tcp)));
    // Finish the handshake now, so a bad certificate fails the open, not the first send.
    if let Stream::Tls(s) = &mut stream {
        while s.conn.is_handshaking() {
            s.conn.complete_io(&mut s.sock).map_err(|e| format!("TLS: {e}"))?;
        }
    }
    stream.tcp().set_read_timeout(Some(POLL)).map_err(|e| e.to_string())?;
    Ok(stream)
}

fn waiting(e: &std::io::Error) -> bool {
    matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut)
}

/// Sends what Elm asks and reads what the server sends, until one side closes. Returns
/// why it closed.
fn run(id: &str, mut stream: Stream, commands: Receiver<Command>) -> String {
    let mut buffer = vec![0u8; CHUNK];
    loop {
        loop {
            match commands.try_recv() {
                Ok(Command::Send(data)) => {
                    if let Err(e) = stream.write_all(&data).and_then(|()| stream.flush()) {
                        if !waiting(&e) {
                            return format!("sending: {e}");
                        }
                    }
                }
                Ok(Command::Close) | Err(TryRecvError::Disconnected) => return "closed by Elm".into(),
                Err(TryRecvError::Empty) => break,
            }
        }
        match stream.read(&mut buffer) {
            Ok(0) => return "closed by the server".into(),
            Ok(n) => elm::send(&ToElm::TlsData { id: id.to_owned(), data: buffer[..n].to_vec() }),
            Err(e) if waiting(&e) => {}
            Err(e) if e.kind() == ErrorKind::UnexpectedEof => return "closed by the server".into(),
            Err(e) => return e.to_string(),
        }
    }
}
