import Testing
@testable import True

@MainActor @Suite struct HubNewTests {
    @Test func newOpensWithCloudSelected() {
        #expect(CloudComposerModel(projects: []).runsOn == .cloud)
    }

    @Test func choiceIsNotRemembered() {
        let m = CloudComposerModel(projects: [])
        m.runsOn = .myMac
        #expect(CloudComposerModel(projects: []).runsOn == .cloud)
    }
}
