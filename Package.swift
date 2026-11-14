// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ContactSheet", platforms: [.macOS(.v14)], products: [.executable(name:"ContactSheet", targets:["ContactSheet"])], targets:[.executableTarget(name:"ContactSheet"),.testTarget(name:"ContactSheetTests",dependencies:["ContactSheet"])])
