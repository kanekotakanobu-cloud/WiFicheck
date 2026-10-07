// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WiFiSurvey",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WiFiSurvey",
            path: "Sources/WiFiSurvey",
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("SystemConfiguration"),
            ]
        )
    ]
)
