//! Code the host's programs share: the texture atlas, the CPU rasteriser, and the
//! kernel's display (KMS) interface.
pub mod atlas;
pub mod drm;
mod font;
pub mod raster;
