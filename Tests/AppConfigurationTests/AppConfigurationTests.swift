import Configuration
import Foundation
import SystemPackage
import Testing
@testable import AppConfiguration

@Test
func configSearchPathOrder() {
    let paths = ConfigurationLoader.candidatePaths(environment: [
        "HOME": "/home/me",
        "XDG_CONFIG_HOME": "/xdg"
    ])
    #expect(paths == [
        "himalaya-mcp.json",
        "/xdg/himalaya-mcp/config.json",
        "/home/me/.config/himalaya-mcp/config.yml",
        "/home/me/.himalayamcprc"
    ])
}

@Test
func configExplicitOverrideIsHighestPriority() {
    let paths = ConfigurationLoader.candidatePaths(environment: [
        "HIMALAYA_MCP_CONFIG": "/custom/cfg.json",
        "HOME": "/home/me"
    ])
    #expect(paths.first == "/custom/cfg.json")
    // XDG defaults to ~/.config when unset.
    #expect(paths.contains("/home/me/.config/himalaya-mcp/config.json"))
    #expect(paths.contains("/home/me/.config/himalaya-mcp/config.yml"))
}

@Test
func yamlConfigFileParsesSettings() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("config.yml")
    try Data("""
    himalaya:
      version: v2
      folder: Inbox
      timeout: 5000
    """.utf8).write(to: file)

    let provider = try await FileProvider<YAMLSnapshot>(filePath: FilePath(file.path))
    let settings = HimalayaSettings(config: ConfigReader(providers: [provider]))
    #expect(settings.version == .v2)
    #expect(settings.folder == "Inbox")
    #expect(settings.timeoutMilliseconds == 5_000)
}

@Test
func experimentalFlagReadsFromEnvironment() {
    let config = ConfigReader(
        provider: EnvironmentVariablesProvider(environmentVariables: ["EXPERIMENTAL_ENABLED": "true"])
    )

    #expect(FeatureFlags(config: config).experimentalEnabled == true)
}

@Test
func experimentalFlagDefaultsToFalse() {
    let config = ConfigReader(provider: EnvironmentVariablesProvider(environmentVariables: [:]))

    #expect(FeatureFlags(config: config).experimentalEnabled == false)
}

@Test
func himalayaSettingsReadFromEnvironment() {
    let config = ConfigReader(provider: EnvironmentVariablesProvider(environmentVariables: [
        "HIMALAYA_ACCOUNT": "work",
        "HIMALAYA_FOLDER": "Archive",
        "HIMALAYA_TIMEOUT": "5000"
    ]))
    let settings = HimalayaSettings(config: config)

    #expect(settings.account == "work")
    #expect(settings.folder == "Archive")
    #expect(settings.timeoutMilliseconds == 5_000)
}

@Test
func himalayaSettingsDefaults() {
    let settings = HimalayaSettings(config: ConfigReader(
        provider: EnvironmentVariablesProvider(environmentVariables: [:])
    ))

    #expect(settings.account == nil) // himalaya's default account
    #expect(settings.folder == nil) // himalaya's default folder (INBOX)
    #expect(settings.timeoutMilliseconds == 120_000) // 2 minutes
    #expect(settings.version == .v1) // default to v1
}

@Test
func himalayaVersionParsing() {
    #expect(HimalayaVersion(string: nil) == .v1)
    #expect(HimalayaVersion(string: "") == .v1)
    #expect(HimalayaVersion(string: "garbage") == .v1)
    #expect(HimalayaVersion(string: "1") == .v1)
    #expect(HimalayaVersion(string: "v1") == .v1)
    #expect(HimalayaVersion(string: "2") == .v2)
    #expect(HimalayaVersion(string: "V2") == .v2)
}

@Test
func himalayaVersionReadsFromEnvironment() {
    let config = ConfigReader(provider: EnvironmentVariablesProvider(
        environmentVariables: ["HIMALAYA_VERSION": "v2"]
    ))
    #expect(HimalayaSettings(config: config).version == .v2)
}
