import AppConfiguration

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
        HimalayaServiceDefault(executable: container.make(ExecutableServiceKey.self))
    }
    app.register(HimalayaDialectKey.self) { _ in
        switch settings.version {
        case .v1: HimalayaDialectV1(defaultAccount: settings.account, defaultFolder: settings.folder)
        case .v2: HimalayaDialectV2(defaultAccount: settings.account, defaultFolder: settings.folder)
        }
    }
    app.register(MMLServiceKey.self) { container in
        MMLServiceDefault(executable: container.make(ExecutableServiceKey.self))
    }
    app.register(EmailComposerKey.self) { _ in EmailComposerDefault() }

    let mmlService = app.make(MMLServiceKey.self)
    let himalayaService = app.make(HimalayaServiceKey.self)
    let capabilities = buildCapabilities(
        himalayaService: himalayaService,
        mmlService: mmlService,
        settings: settings
    )
    app.register(CapabilitiesKey.self) { _ in capabilities }

    app.register(HimalayaSettingsServiceKey.self, scope: .transient) { _ in settings }
    app.register(FeatureFlagsServiceKey.self, scope: .transient) { _ in flags }
}

/// Probes himalaya and mml once at startup, caches the result.
private func buildCapabilities(
    himalayaService: any HimalayaService,
    mmlService: any MMLService,
    settings: HimalayaSettings
) -> Capabilities {
    let himalayaVersion = (try? himalayaService.run(arguments: ["--version"])) ?? "unknown"
    let family: HimalayaFamily = settings.version == .v2 ? .v2 : .v1
    let mmlPresent = mmlService.isAvailable()
    let mmlVersion = mmlService.version()

    let strategy: TemplateStrategy = if mmlPresent {
        .mmlExternal
    } else if family == .v1 {
        .himalayaBuiltin
    } else {
        .unavailable
    }

    return Capabilities(
        himalayaVersion: himalayaVersion,
        himalayaFamily: family,
        mmlPresent: mmlPresent,
        mmlVersion: mmlVersion,
        templateStrategy: strategy
    )
}
