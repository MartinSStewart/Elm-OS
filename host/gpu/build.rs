// Mesa's libraries (libEGL, libGLESv2, libgbm) come from Alpine (tools/fetch-mesa.py);
// the Makefile says where with ELMOS_MESA_LIB.
fn main() {
    println!("cargo:rerun-if-env-changed=ELMOS_MESA_LIB");
    if let Ok(dir) = std::env::var("ELMOS_MESA_LIB") {
        println!("cargo:rustc-link-search=native={dir}");
    }
}
