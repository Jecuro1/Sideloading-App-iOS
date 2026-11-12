// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IPABeam",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "IPABeam",
            path: "Sources/IPABeam"
        )
    ]
)
