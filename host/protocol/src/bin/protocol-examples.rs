//! Prints examples.json's messages as the bytes that go on the wire, in hex, for
//! elm/tests/ProtocolTest.elm (tools/protocol-examples.py writes them into an Elm
//! module): {"toHost": [one Effect each], "fromHost": [one ToElm each]}.

use protocol::{Effect, ToElm};
use serde_json::Value;

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn main() {
    let all: Value = serde_json::from_str(include_str!("../../examples.json")).unwrap();
    let list = |direction: &str| all[direction].as_array().unwrap().clone();
    let to_host: Vec<String> = list("toHost")
        .into_iter()
        .map(|e| {
            let effect: Effect = serde_json::from_value(e).unwrap();
            hex(&postcard::to_allocvec(&effect).unwrap())
        })
        .collect();
    let from_host: Vec<String> = list("fromHost")
        .into_iter()
        .map(|m| hex(&serde_json::from_value::<ToElm>(m).unwrap().to_bytes()))
        .collect();
    println!("{}", serde_json::json!({ "toHost": to_host, "fromHost": from_host }));
}
