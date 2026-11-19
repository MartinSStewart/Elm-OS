//! Lists the sprite files (sprites/ at the top of the repository) for src/sprites.rs:
//! writes $OUT_DIR/sprite_files.rs, every file there by name, in name order, with its
//! bytes compiled in. Cargo runs this again when the folder changes.

use std::fmt::Write;
use std::path::Path;

fn main() {
    let dir = Path::new(&std::env::var("CARGO_MANIFEST_DIR").unwrap()).join("../../sprites").canonicalize().expect("no sprites folder");
    println!("cargo:rerun-if-changed={}", dir.display());
    let mut names: Vec<String> = std::fs::read_dir(&dir)
        .expect("can't list the sprites folder")
        .map(|e| e.unwrap().file_name().into_string().expect("a sprite file name isn't UTF-8"))
        .filter(|n| n.ends_with(".webp") || n == "hot-spots.txt")
        .collect();
    names.sort();
    let mut out = String::from("pub static FILES: &[(&str, &[u8])] = &[\n");
    for n in &names {
        let path = dir.join(n);
        println!("cargo:rerun-if-changed={}", path.display());
        writeln!(out, "    ({n:?}, include_bytes!({:?})),", path.display().to_string()).unwrap();
    }
    out.push_str("];\n");
    std::fs::write(Path::new(&std::env::var("OUT_DIR").unwrap()).join("sprite_files.rs"), out).unwrap();
}
