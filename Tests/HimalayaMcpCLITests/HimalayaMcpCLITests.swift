import App
import AppConfiguration
import CascadeKit
import MCP
import Testing
@testable import HimalayaMcpCLI

@Test
func decodeArgumentsTreatsNilAsEmptyObject() throws {
    let input = try decodeArguments(EmptyInput.self, from: nil)

    _ = input // EmptyInput has no fields; decoding from an empty bag must not throw.
}

@Test
func deleteEmailHiddenUnlessExperimentalEnabled() {
    let off = ToolHandler.visible(featureFlags: FeatureFlags(experimentalEnabled: false))
    #expect(off.contains { $0.tool.name == "delete_email" } == false)
    // Non-experimental tools stay visible.
    #expect(off.contains { $0.tool.name == "list_emails" } == true)

    let on = ToolHandler.visible(featureFlags: FeatureFlags(experimentalEnabled: true))
    #expect(on.contains { $0.tool.name == "delete_email" } == true)
}

@Test
func configureRegistersResolvableServices() async throws {
    // configure() and the container live in the executable now — exercise them on a
    // fresh container so the shared `app` isn't mutated.
    let testApp = Application()
    await configure(testApp)

    let toolchain = try testApp.make(ExecutableServiceKey.self).run(
        executable: "swift",
        arguments: ["--version"]
    )
    #expect(toolchain.contains("Swift version"))

    _ = testApp.make(FeatureFlagsServiceKey.self) // resolves (default false, no env/file)
}
