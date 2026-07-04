import Testing
import Configuration
@testable import AppConfiguration

@Test func experimentalFlagReadsFromEnvironment() {
    let config = ConfigReader(
        provider: EnvironmentVariablesProvider(environmentVariables: ["EXPERIMENTAL_ENABLED": "true"])
    )

    #expect(FeatureFlags(config: config).experimentalEnabled == true)
}

@Test func experimentalFlagDefaultsToFalse() {
    let config = ConfigReader(provider: EnvironmentVariablesProvider(environmentVariables: [:]))

    #expect(FeatureFlags(config: config).experimentalEnabled == false)
}
