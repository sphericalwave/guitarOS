import Testing
@testable import guitar

struct AppSectionTests {
    @Test func fourSectionsInNavigationOrder() {
        #expect(AppSection.allCases == [.today, .practice, .progress, .tools])
    }

    @Test func rawValuesStayStableBecauseTheyArePersisted() {
        #expect(AppSection.allCases.map(\.rawValue) == ["today", "practice", "progress", "tools"])
    }
}
