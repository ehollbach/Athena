// swift-tools-version: 5.9

import PackageDescription

// AthenaEngine.xcframework is kneejerk built for iPhone: run scripts/build-ios.sh first.
let package = Package(
    name: "athena_native",
    platforms: [
        .iOS("16.4")
    ],
    products: [
        .library(name: "athena-native", targets: ["athena_native"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "athena_native",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "AthenaEngine",
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        ),
        .binaryTarget(name: "AthenaEngine", path: "AthenaEngine.xcframework"),
    ]
)
