//! Code the host's programs share: the texture atlas, the image texture, the CPU rasteriser, and the
//! kernel's display (KMS) interface.
pub mod atlas;
pub mod cursor;
pub mod drm;
pub mod images;
pub mod msglog;
mod font;
pub mod raster;
pub mod sprites;
