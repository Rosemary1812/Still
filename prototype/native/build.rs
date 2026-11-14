use std::{env, path::PathBuf, process::Command};
fn main() {
    println!("cargo:rerun-if-changed=macos/PhotoBridge.swift");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") { return; }
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let status = Command::new("xcrun").args(["swiftc", "-parse-as-library", "-emit-library", "-static", "-module-name", "ContactSheetPhotoBridge", "macos/PhotoBridge.swift", "-module-cache-path"]).arg(out.join("swift-cache")).arg("-target").arg(if env::var("CARGO_CFG_TARGET_ARCH").as_deref() == Ok("aarch64") { "arm64-apple-macosx14.0" } else { "x86_64-apple-macosx14.0" }).arg("-o").arg(out.join("libContactSheetPhotoBridge.a")).status().expect("Swift compiler is required for Apple Photos");
    assert!(status.success(), "Apple Photos bridge compilation failed");
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=ContactSheetPhotoBridge");
    println!("cargo:rustc-link-lib=framework=Photos");
    println!("cargo:rustc-link-lib=framework=AppKit");
    println!("cargo:rustc-link-search=native=/usr/lib/swift");
    println!("cargo:rustc-link-lib=dylib=swiftCore");
    println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");
}
