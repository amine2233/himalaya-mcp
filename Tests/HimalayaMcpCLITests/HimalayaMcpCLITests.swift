import Testing
import MCP
import CascadeKit
import AppConfiguration
import App
@testable import HimalayaMcpCLI

@Test func decodeArgumentsTreatsNilAsEmptyObject() throws {
    let input = try decodeArguments(EmptyInput.self, from: nil)

    _ = input  // EmptyInput has no fields; decoding from an empty bag must not throw.
}

@Test func configureRegistersResolvableServices() async throws {
    // configure() and the container live in the executable now — exercise them on a
    // fresh container so the shared `app` isn't mutated.
    let testApp = Application()
    await configure(testApp)

    let toolchain = try testApp.make(ExecutableServiceKey.self).run(executable: "swift", arguments: ["--version"])
    #expect(toolchain.contains("Swift version"))

    _ = testApp.make(FeatureFlagsServiceKey.self)  // resolves (default false, no env/file)
}
