//! How the Elm program's process and the host's talk, over the Unix socket the host
//! gives the Elm program when it starts it (host/init/src/elm.rs, host/link): a
//! stream of messages, each a kind byte, its length as a little-endian u32, and that
//! many bytes.
//!
//! host/link includes this file as it is (`#[path]`), rather than depending on this
//! crate, so that the Elm program doesn't carry serde.

use std::io::{self, Read, Write};

/// Elm -> host: what Elm sent on its `toHost` port, a JSON list of effects.
pub const TO_HOST: u8 = 1;
/// Elm -> host: what Elm sent on its `render` port, the scene as bytes.
pub const RENDER: u8 = 2;
/// Host -> Elm: one JSON message for Elm's `fromHost` port.
pub const FROM_HOST: u8 = 3;

/// No message is anywhere near this long; a longer one means the stream is broken.
const MAX_LENGTH: usize = 1 << 28;

/// Writes one message in a single write, so that writers taking turns can't interleave.
pub fn write_message(w: &mut impl Write, kind: u8, payload: &[u8]) -> io::Result<()> {
    let mut message = Vec::with_capacity(5 + payload.len());
    message.push(kind);
    message.extend_from_slice(&(payload.len() as u32).to_le_bytes());
    message.extend_from_slice(payload);
    w.write_all(&message)
}

/// The next message's kind and payload; an UnexpectedEof error when the other end has
/// closed the socket.
pub fn read_message(r: &mut impl Read) -> io::Result<(u8, Vec<u8>)> {
    let mut header = [0u8; 5];
    r.read_exact(&mut header)?;
    let length = u32::from_le_bytes([header[1], header[2], header[3], header[4]]) as usize;
    if length > MAX_LENGTH {
        return Err(io::Error::new(io::ErrorKind::InvalidData, format!("a message of {length} bytes")));
    }
    let mut payload = vec![0u8; length];
    r.read_exact(&mut payload)?;
    Ok((header[0], payload))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn messages_read_back() {
        let mut stream = Vec::new();
        write_message(&mut stream, TO_HOST, b"[]").unwrap();
        write_message(&mut stream, RENDER, &[]).unwrap();
        write_message(&mut stream, FROM_HOST, "{\"t\":\"é\"}".as_bytes()).unwrap();
        let mut r = &stream[..];
        assert_eq!(read_message(&mut r).unwrap(), (TO_HOST, b"[]".to_vec()));
        assert_eq!(read_message(&mut r).unwrap(), (RENDER, vec![]));
        assert_eq!(read_message(&mut r).unwrap(), (FROM_HOST, "{\"t\":\"é\"}".as_bytes().to_vec()));
        assert_eq!(read_message(&mut r).unwrap_err().kind(), io::ErrorKind::UnexpectedEof);
    }
}
