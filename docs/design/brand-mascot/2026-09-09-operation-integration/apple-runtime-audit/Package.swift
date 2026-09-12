// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TogetherRiveAssetAudit",
    platforms: [.macOS("13.1")],
    dependencies: [.package(url: "https://github.com/rive-app/rive-ios", exact: "6.25.1")],
    targets: [.executableTarget(
        name: "TogetherRiveAssetAudit",
        dependencies: [.product(name: "RiveRuntime", package: "rive-ios")]
    )]
)
