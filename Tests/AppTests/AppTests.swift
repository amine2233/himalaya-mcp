import Testing
import Foundation
import Synchronization
import CascadeKit
import AppConfiguration
@testable import App

/// A stub executable service so requests can be tested without shelling out to `swift`.
private struct StubExecutable: ExecutableService {
    let output: String
    func run(executable: String, arguments: [String]) throws -> String { output }
}

@Test func executableServiceResolvesFromContainer() throws {
    let app = Application()
    app.register(ExecutableServiceKey.self) { _ in StubExecutable(output: "himalaya 1.0.0") }

    let output = try app.make(ExecutableServiceKey.self).run(executable: "himalaya", arguments: ["--version"])

    #expect(output == "himalaya 1.0.0")
}

@Test func featureFlagsRegistrationResolves() {
    let app = Application()
    app.register(FeatureFlagsServiceKey.self, scope: .transient) { _ in
        FeatureFlags(experimentalEnabled: true)
    }

    #expect(app.make(FeatureFlagsServiceKey.self).experimentalEnabled == true)
}

@Test func singletonIsCachedAndTransientIsRebuilt() {
    let singletonBuilds = Mutex(0)
    let transientBuilds = Mutex(0)
    let app = Application()

    app.register(ExecutableServiceKey.self, scope: .singleton) { _ in
        singletonBuilds.withLock { $0 += 1 }
        return ExecutableServiceDefault()
    }
    app.register(FeatureFlagsServiceKey.self, scope: .transient) { _ in
        transientBuilds.withLock { $0 += 1 }
        return FeatureFlags(experimentalEnabled: false)
    }

    _ = app.make(ExecutableServiceKey.self)
    _ = app.make(ExecutableServiceKey.self)
    _ = app.make(FeatureFlagsServiceKey.self)
    _ = app.make(FeatureFlagsServiceKey.self)

    #expect(singletonBuilds.withLock { $0 } == 1)   // built once, then cached
    #expect(transientBuilds.withLock { $0 } == 2)   // rebuilt each time
}
