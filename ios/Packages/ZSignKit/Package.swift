// swift-tools-version:5.9
import PackageDescription

let zsignHeaders: [String] = [
    "zsign/src",
    "zsign/src/common",
    "zsign/src/third-party/zlib",
    "zsign/src/third-party/minizip"
]

let package = Package(
    name: "ZSignKit",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "ZSignKit", targets: ["ZSignKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/krzyzanowskim/OpenSSL", exact: "3.3.3001")
    ],
    targets: [
        // zsign (C++) + zlib/minizip + small C glue (getopt reset, local CA generator)
        .target(
            name: "CZSign",
            dependencies: [.product(name: "OpenSSL", package: "OpenSSL")],
            path: "Sources/CZSign",
            exclude: ["zsign/LICENSE", "zsign/.version"],
            cSettings: zsignHeaders.map { .headerSearchPath($0) } + [
                .define("ZSIGN_VERSION", to: "1.1.3"),
                .unsafeFlags(["-w"])
            ],
            cxxSettings: zsignHeaders.map { .headerSearchPath($0) } + [
                .define("ZSIGN_VERSION", to: "1.1.3"),
                .unsafeFlags(["-w"])
            ]
        ),
        .target(
            name: "ZSignKit",
            dependencies: ["CZSign"],
            path: "Sources/ZSignKit"
        )
    ],
    cxxLanguageStandard: .gnucxx14
)
