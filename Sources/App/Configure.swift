import AppConfiguration
import CascadeKit

/// One-stop dependency configuration, à la Vapor's `configure.swift`.
///
/// Register every service here, then run the app. Called once at startup, before
/// argument parsing. Feature flags are `.transient` so this resolved value always
/// replaces the default (no stale singleton cache).
public func configure(_ app: Application) async {
    let (flags, settings) = await ConfigurationLoader.resolveAll()

    app.register(ExecutableServiceKey.self) { _ in
        ExecutableServiceDefault(timeoutMilliseconds: settings.timeoutMilliseconds)
    }
    app.register(HimalayaServiceKey.self) { container in
        HimalayaServiceDefault(
            executable: container.make(ExecutableServiceKey.self),
            defaultAccount: settings.account,
            defaultFolder: settings.folder
        )
    }

    app.register(HimalayaSettingsServiceKey.self, scope: .transient) { _ in settings }
    app.register(FeatureFlagsServiceKey.self, scope: .transient) { _ in flags }
}
