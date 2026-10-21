import Foundation

/// Resources are processed individually so a host-only reference engine's network
/// is never copied into the native app. Older exported bundles remain readable.
enum CoreResources {
    static func url(forResource name: String, withExtension ext: String, subdirectory: String? = nil) -> URL? {
        Bundle.module.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: name, withExtension: ext)
    }
}
