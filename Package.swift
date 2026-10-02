// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OpenBORMacV2",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenBORMacV2", targets: ["OpenBORMacV2"])
    ],
    targets: [
        .executableTarget(
            name: "OpenBORMacV2",
            path: "OpenBORMacV2",
            exclude: [
                "README.md",
                "Docs",
                "App/.gitkeep",
                "Host/.gitkeep",
                "Renderer/.gitkeep",
                "EngineBridge/.gitkeep",
                "EngineBridge/README.md",
                "Info.plist"
            ],
            sources: [
                "App",
                "Host",
                "Renderer",
                "EngineBridge"
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("GameController"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("OpenGL"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)
