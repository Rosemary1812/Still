use std::{env, path::PathBuf, process::Command};

fn main() {
    println!("cargo:rerun-if-changed=macos/PhotoBridge.swift");
    let target = env::var("TARGET").unwrap();
    let arch = if target.starts_with("aarch64") {
        "arm64"
    } else {
        "x86_64"
    };
    let (sdk, swift_target) = match env::var("CARGO_CFG_TARGET_OS").unwrap().as_str() {
        "macos" => ("macosx", format!("{arch}-apple-macosx14.0")),
        "ios" if target.ends_with("-sim") || arch == "x86_64" => {
            ("iphonesimulator", format!("{arch}-apple-ios17.0-simulator"))
        }
        "ios" => ("iphoneos", format!("{arch}-apple-ios17.0")),
        _ => return,
    };
    let sdk_path = Command::new("xcrun")
        .args(["--sdk", sdk, "--show-sdk-path"])
        .output()
        .unwrap();
    assert!(sdk_path.status.success(), "Apple SDK unavailable");
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let status = Command::new("xcrun")
        .args([
            "swiftc",
            "-sdk",
            String::from_utf8(sdk_path.stdout).unwrap().trim(),
            "-target",
            &swift_target,
            "-parse-as-library",
            "-emit-library",
            "-static",
            "-module-name",
            "ContactSheetPhotoBridge",
            "macos/PhotoBridge.swift",
            "-module-cache-path",
        ])
        .arg(out.join("swift-cache"))
        .arg("-o")
        .arg(out.join("libContactSheetPhotoBridge.a"))
        .status()
        .expect("Swift compiler is required for Apple Photos");
    assert!(status.success(), "Apple Photos bridge compilation failed");
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=ContactSheetPhotoBridge");
    for framework in [
        "Photos",
        "PhotosUI",
        "ImageIO",
        "AVFoundation",
        "UniformTypeIdentifiers",
        if sdk == "macosx" { "AppKit" } else { "UIKit" },
    ] {
        println!("cargo:rustc-link-lib=framework={framework}");
    }
    // Swift compatibility libraries for the selected platform are distributed with Xcode.
    let compiler = Command::new("xcrun")
        .args(["--find", "swiftc"])
        .output()
        .unwrap();
    let compiler = PathBuf::from(String::from_utf8(compiler.stdout).unwrap().trim());
    let runtime = compiler.parent().unwrap().join("../lib/swift").join(sdk);
    println!("cargo:rustc-link-search=native={}", runtime.display());
    println!("cargo:rustc-link-search=native=/usr/lib/swift");
    println!("cargo:rustc-link-lib=dylib=swiftCore");
    println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");
}
