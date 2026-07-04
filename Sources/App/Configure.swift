import AppConfiguration
import CascadeKit

/// One-stop dependency configuration, à la Vapor's `configure.swift`.
///
/// Register every service here, then run the app. Called once at startup, before
/// argument parsing. Feature flags are `.transient` so this resolved value always
/// replaces the default (no stale singleton cache).
public func configure(_ app: Application) async {
    app.register(ExecutableServiceKey.self) { _ in ExecutableServiceDefault() }
    app.register(HimalayaServiceKey.self) { container in
        HimalayaServiceDefault(executable: container.make(ExecutableServiceKey.self))
    }

    let flags = await ConfigurationLoader.resolve()
    app.register(FeatureFlagsServiceKey.self, scope: .transient) { _ in flags }
}
