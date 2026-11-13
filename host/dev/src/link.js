// The Elm program's end of its link to the dev runner when it is eco's JavaScript
// build (build/elm.js), run by Node: what host/link is to the native build. The dev
// runner (main.rs) starts `node -e <this> <elm.js>` with its socket as fd 3 and the
// same framing (host/protocol/src/link.rs): a kind byte, the length as a
// little-endian u32, then the bytes. Both ports carry postcard bytes, passed on as
// they are.

const net = require("net");
const path = require("path");

const TO_HOST = 1;
const FROM_HOST = 3;

const { Elm } = require(path.resolve(process.argv[process.argv.length - 1]));
const app = Elm.ElmOs.init();
const socket = new net.Socket({ fd: 3, readable: true, writable: true });

app.ports.toHost.subscribe((bytes) => {
  const header = Buffer.alloc(5);
  header[0] = TO_HOST;
  header.writeUInt32LE(bytes.byteLength, 1);
  socket.write(Buffer.concat([header, Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength)]));
});

let pending = Buffer.alloc(0);
socket.on("data", (chunk) => {
  pending = pending.length === 0 ? chunk : Buffer.concat([pending, chunk]);
  while (pending.length >= 5) {
    const length = pending.readUInt32LE(1);
    if (pending.length < 5 + length) {
      break;
    }
    const kind = pending[0];
    // A copy: `pending` is reused for what comes next.
    const message = Uint8Array.prototype.slice.call(pending, 5, 5 + length);
    pending = pending.subarray(5 + length);
    if (kind === FROM_HOST) {
      app.ports.fromHost.send(message);
    } else {
      process.stderr.write(`[elm] a message of kind ${kind} from the host\n`);
    }
  }
});

// When the dev runner goes, so do we.
socket.on("close", () => process.exit(0));
socket.on("error", () => process.exit(0));
