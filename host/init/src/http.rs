//! HTTP requests for Elm: each one on its own short-lived thread, with ureq. HTTPS
//! goes through rustls (crypto from ring) and checks servers against Mozilla's CA
//! list, compiled in from the webpki-roots crate, so /init needs no OpenSSL and no
//! certificate files. `make refresh` updates both with `cargo update`.
//!
//!   {"t":"http","id":ID,"method":M,"url":U,"headers":[[NAME,VALUE],...],"body":B,"timeoutMs":MS|null}
//!   -> {"t":"httpResponse","id":ID,"status":N,"body":B}   any status, 404 included
//!   -> {"t":"httpError","id":ID,"error":"badUrl"|"timeout"|"network","message":M}

use protocol::{HttpFailure, ToElm};
use std::sync::OnceLock;
use std::time::Duration;

use crate::elm;

pub use protocol::HttpRequest as Request;

/// Responses bigger than this fail rather than fill the memory.
const MAX_BODY: u64 = 16 << 20;

fn agent() -> &'static ureq::Agent {
    static AGENT: OnceLock<ureq::Agent> = OnceLock::new();
    AGENT.get_or_init(|| {
        ureq::Agent::config_builder()
            .http_status_as_error(false)
            .user_agent("ElmOS")
            .build()
            .new_agent()
    })
}

enum Failure {
    BadUrl(String),
    Timeout,
    Network(String),
}

fn run(req: &Request) -> Result<(u16, String), Failure> {
    let mut builder = ureq::http::Request::builder()
        .method(req.method.as_str())
        .uri(req.url.as_str());
    for (name, value) in &req.headers {
        builder = builder.header(name.as_str(), value.as_str());
    }
    let timeout = Duration::from_secs_f64(req.timeout_ms.unwrap_or(30_000.0).max(1.0) / 1000.0);
    let result = if req.body.is_empty() {
        let r = builder.body(()).map_err(|e| Failure::BadUrl(e.to_string()))?;
        agent().run(agent().configure_request(r).timeout_global(Some(timeout)).build())
    } else {
        let r = builder
            .body(req.body.clone())
            .map_err(|e| Failure::BadUrl(e.to_string()))?;
        agent().run(agent().configure_request(r).timeout_global(Some(timeout)).build())
    };
    let mut response = result.map_err(|e| match e {
        ureq::Error::BadUri(m) => Failure::BadUrl(m),
        ureq::Error::Http(e) => Failure::BadUrl(e.to_string()),
        ureq::Error::Timeout(_) => Failure::Timeout,
        e => Failure::Network(e.to_string()),
    })?;
    let status = response.status().as_u16();
    let body = response
        .body_mut()
        .with_config()
        .limit(MAX_BODY)
        .read_to_string()
        .map_err(|e| match e {
            ureq::Error::Timeout(_) => Failure::Timeout,
            e => Failure::Network(e.to_string()),
        })?;
    Ok((status, body))
}

pub fn request(req: Request) {
    elm::http_started(&req.id);
    std::thread::Builder::new()
        .name("http".into())
        .spawn(move || {
            let msg = match run(&req) {
                Ok((status, body)) => {
                    log!(
                        "http",
                        "{} {} -> {} ({} bytes)",
                        req.method,
                        req.url,
                        status,
                        body.len()
                    );
                    ToElm::HttpResponse { id: req.id.clone(), status, body }
                }
                Err(f) => {
                    let (error, message) = match f {
                        Failure::BadUrl(m) => (HttpFailure::BadUrl, m),
                        Failure::Timeout => (HttpFailure::Timeout, "the server took too long".to_owned()),
                        Failure::Network(m) => (HttpFailure::Network, m),
                    };
                    log!("http", "{} {} failed: {:?} {}", req.method, req.url, error, message);
                    ToElm::HttpError { id: req.id.clone(), error, message }
                }
            };
            elm::send(&msg);
        })
        .ok();
}
