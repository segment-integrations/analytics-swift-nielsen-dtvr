
// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SegmentNielsenDTVR",
    platforms: [
        .macOS("10.15"),
        .iOS("13.0"),
        .tvOS("11.0"),
        .watchOS("7.1")
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "SegmentNielsenDTVR",
            targets: ["SegmentNielsenDTVR"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(
            name: "Segment",
            url: "https://github.com/segmentio/analytics-swift.git",
            from: "1.4.0"
        ),
        .package(
            name: "NielsenAppApi",
            url: "https://github.com/NielsenDigitalSDK/nielsenappsdk-ios-dynamic-spm-global",
            from: "8.2.0"
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "SegmentNielsenDTVR",
            dependencies: ["Segment", .product(
                name: "NielsenAppApi",
                package: "NielsenAppApi")])
        
        // TESTS ARE HANDLED VIA THE EXAMPLE APP.
    ]
)

