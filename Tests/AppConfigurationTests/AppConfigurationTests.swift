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
func accountFromReadsFromEnvironmentKey() {
    let config = ConfigReader(provider: EnvironmentVariablesProvider(environmentVariables: [
        "HIMALAYA_ACCOUNTS_OUTLOOK_FROM": "amine.bensalah@outlook.com"
    ]))
    let accounts = ConfigurationLoader.accountFrom(from: config)

    #expect(accounts.from(forAccount: "outlook") == "amine.bensalah@outlook.com")
    #expect(accounts.from(forAccount: "proton") == nil)
    #expect(AccountFromNames.none.from(forAccount: "outlook") == nil)
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
