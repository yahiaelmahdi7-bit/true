import Testing
import Foundation
@testable import True

private let apps = AppIndex(names: ["Safari", "Google Chrome", "Dia", "Music"])
private func session() -> NovaInstantSession { NovaInstantSession(apps: apps, panes: ["True CTO", "Atlas"], prefixWait: 0.25) }
private func words(_ s: String) -> [String] { s.split(separator: " ").map(String.init) }
private func m(_ s: String) -> NovaInstant.Match { NovaInstant.match(words(s), apps: apps, panes: ["Atlas"]) }
private func acts(_ steps: [NovaInstantSession.Step]) -> [InstantVerb] { steps.compactMap { if case .act(let v) = $0.kind { return v } else { return nil } } }

@Suite struct NovaTabTests {
    @Test func matchesWithBrowser() {
        #expect(m("pull up the youtube tab on dia") == .act(.switchTab(query: "youtube", browser: "Dia"), ambiguous: false))
        #expect(m("can you pull up the youtube tab on dia") == .act(.switchTab(query: "youtube", browser: "Dia"), ambiguous: false))
        #expect(m("could you please go to my github tab in chrome") == .act(.switchTab(query: "github", browser: "Google Chrome"), ambiguous: false))
        #expect(m("go to my github tab in google chrome") == .act(.switchTab(query: "github", browser: "Google Chrome"), ambiguous: false))
        #expect(m("show me the reddit tab on brave") == .act(.switchTab(query: "reddit", browser: "Brave Browser"), ambiguous: false))
    }
    @Test func noBrowserWaitsThePrefixBeat() {
        #expect(m("switch to the gmail tab") == .act(.switchTab(query: "gmail", browser: nil), ambiguous: true))
        #expect(m("show the github tab") == .act(.switchTab(query: "github", browser: nil), ambiguous: true))
        #expect(m("open the youtube music tab") == .act(.switchTab(query: "youtube music", browser: nil), ambiguous: true))
        var s = session(); let t0 = Date()
        #expect(acts(s.feed("pull up the youtube tab", now: t0)).isEmpty)
        #expect(acts(s.feed("pull up the youtube tab on", now: t0.addingTimeInterval(0.1))).isEmpty)       // half a browser phrase: wait
        #expect(acts(s.feed("pull up the youtube tab on dia", now: t0.addingTimeInterval(0.15))) == [.switchTab(query: "youtube", browser: "Dia")])
        var s2 = session()
        _ = s2.feed("switch to the gmail tab", now: t0)
        #expect(acts(s2.feed("switch to the gmail tab", now: t0.addingTimeInterval(0.3))) == [.switchTab(query: "gmail", browser: nil)])
    }
    /// Live 2026-10-11: he said it without "tab" and it fell to the brain, whose open_url parked for 30 s.
    @Test func siteOnBrowserWithoutTheWordTab() {
        #expect(m("pull up youtube on dia") == .act(.switchTab(query: "youtube", browser: "Dia"), ambiguous: false))
        #expect(m("open youtube on dear") == .act(.switchTab(query: "youtube", browser: "Dia"), ambiguous: false))
        #expect(m("can you pull up gmail in chrome") == .act(.switchTab(query: "gmail", browser: "Google Chrome"), ambiguous: false))
        #expect(NovaTabs.parse(words("pull up youtube on")) == nil)            // half a browser phrase
        #expect(NovaTabs.parse(words("put it on the table")) == nil)
        #expect(m("open youtube") == .act(.openSite(name: "YouTube", url: "https://www.youtube.com"), ambiguous: false))   // unchanged
        #expect(NovaInstant.sites["youtube"]?.url == "https://www.youtube.com")   // fallback opens from the fixed table only
    }
    @Test func incompleteOrOtherSpeechDoesNotMatch() {
        #expect(m("pull up the tab") == .none)                                        // no query word
        #expect(NovaTabs.parse(words("pull up the youtube")) == nil)                  // "tab" not said yet
        #expect(NovaTabs.parse(words("pull up the youtube tab in google")) == nil)    // half a browser
        #expect(NovaTabs.parse(words("what's a tab")) == nil)
        #expect(NovaTabs.parse(words("open the tab bar")) == nil)
        #expect(NovaTabs.parse(words("open the tab")) == nil)
        #expect(m("open youtube") == .act(.openSite(name: "YouTube", url: "https://www.youtube.com"), ambiguous: false))
        #expect(m("open safari") == .act(.openApp("Safari"), ambiguous: false))
    }
    @Test func tellsStillWin() {
        var s = session()
        #expect(acts(s.feed("tell true-cto to open the tab bar", now: Date())).isEmpty)
        #expect(s.tellMatched)
        var s2 = session()
        #expect(acts(s2.feed("tell atlas to pull up the youtube tab on dia", now: Date())).isEmpty)
    }
    @Test func verbBasics() {
        let v = InstantVerb.switchTab(query: "youtube", browser: nil)
        #expect(v.spoken == "pulled up youtube")
        #expect(!v.undoable)
        #expect(NovaInstantTools.names.contains("switch_tab"))
        let (tool, input) = NovaInstantRunner.tool(for: .switchTab(query: "gmail", browser: "Dia"))
        #expect(tool == "switch_tab" && input["query"] as? String == "gmail" && input["browser"] as? String == "Dia")
    }
    @Test func browserResolutionOrder() {
        let all = ["Finder", "Safari", "Google Chrome", "Dia"]
        #expect(NovaTabs.resolveBrowser(named: "Dia", frontmost: "Safari", running: all) == "Dia")
        #expect(NovaTabs.resolveBrowser(named: "Arc", frontmost: "Safari", running: all) == nil)       // named but not running
        #expect(NovaTabs.resolveBrowser(named: nil, frontmost: "Safari", running: all) == "Safari")    // frontmost browser
        #expect(NovaTabs.resolveBrowser(named: nil, frontmost: "Finder", running: all) == "Dia")       // list order: Dia first
        #expect(NovaTabs.resolveBrowser(named: nil, frontmost: nil, running: ["Safari", "Google Chrome"]) == "Google Chrome")
        #expect(NovaTabs.resolveBrowser(named: nil, frontmost: nil, running: ["Finder"]) == nil)
    }
    @Test func scriptsCarryNoSpokenText() {
        let evil = "x\" & (do shell script \"rm -rf ~\") & \""
        let tabs = [NovaTabs.Tab(window: 1, tab: 2, title: "Inbox", url: "https://mail.google.com")]
        #expect(NovaTabs.pick(evil, in: tabs) == nil)
        for b in NovaTabs.browsers {
            let l = NovaTabs.listScript(b)!, f = NovaTabs.focusScript(b, window: 3, tab: 7)!
            #expect(!l.contains("rm -rf") && !f.contains("rm -rf") && !f.contains("youtube"))
            #expect(f.contains("3") && f.contains("7") && f.contains("activate"))
        }
        #expect(NovaTabs.listScript("Evil\" App") == nil)
        #expect(NovaTabs.focusScript("Dia", window: 0, tab: 1) == nil)
        #expect(NovaTabs.focusScript("Dia", window: 1, tab: 4)!.contains("focus tab 4 of window 1"))
        #expect(NovaTabs.focusScript("Safari", window: 1, tab: 4)!.contains("current tab"))
        #expect(NovaTabs.focusScript("Google Chrome", window: 1, tab: 4)!.contains("active tab index"))
    }
    @Test func pickAndParse() {
        let out = "1\u{1F}1\u{1F}(40) YouTube\u{1F}https://www.youtube.com/\u{1E}1\u{1F}2\u{1F}Gmail\u{1F}https://mail.google.com\u{1E}2\u{1F}1\u{1F}Docs\u{1F}https://youtube.example/docs\u{1E}"
        let tabs = NovaTabs.parseList(out)
        #expect(tabs.count == 3 && tabs[1] == NovaTabs.Tab(window: 1, tab: 2, title: "Gmail", url: "https://mail.google.com"))
        #expect(NovaTabs.pick("YouTube", in: tabs)?.tab == 1)
        #expect(NovaTabs.pick("mail", in: tabs)?.title == "Gmail")
        #expect(NovaTabs.pick("calendar", in: tabs) == nil)
        #expect(NovaTabs.pick("example", in: tabs)?.window == 2)       // URL fallback
    }
}
