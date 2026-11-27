import Configuration
import Testing
@testable import AppConfiguration

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
}
