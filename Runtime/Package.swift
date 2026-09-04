// swift-tools-version: 6.2
import PackageDescription

// Development spike: only the audited, local-loading Qwen subset is staged by
// prepare-runtime.rb. The general Hub/download products are deliberately absent.
let package = Package(
    name: "OpenScreenReaderSpeechRuntime",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OpenScreenReaderSpeechWorker", targets: ["SpeechWorker"])],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.31.4"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.31.4"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", exact: "1.1.9"),
    ],
    targets: [
        .target(name: "MLXAudioCore", dependencies: [
            .product(name: "MLX", package: "mlx-swift")
        ], path: ".generated/Core"),
        .target(name: "MLXAudioCodecs", dependencies: [
            "MLXAudioCore", .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXNN", package: "mlx-swift"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm")
        ], path: ".generated/Codecs"),
        .target(name: "LocalQwen", dependencies: [
            "MLXAudioCore", "MLXAudioCodecs",
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXNN", package: "mlx-swift"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            .product(name: "Tokenizers", package: "swift-transformers")
        ], path: ".generated/Qwen"),
        .executableTarget(name: "SpeechWorker", dependencies: [
            "LocalQwen", "MLXAudioCore",
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm")
        ]),
    ]
)
