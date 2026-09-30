import Testing
import Foundation
@testable import True

@Suite struct BuildFreshnessTests {
    let t0 = Date(timeIntervalSince1970: 1_000)
    @Test func sameStampIsFresh() {
        let s = BinaryStamp(inode: 5, modified: t0)
        #expect(!BuildFreshness.isStale(launched: s, current: s))
    }
    @Test func newInodeIsStale() {
        let s = BinaryStamp(inode: 5, modified: t0)
        #expect(BuildFreshness.isStale(launched: s, current: BinaryStamp(inode: 6, modified: t0)))
    }
    @Test func newMtimeIsStale() {
        let s = BinaryStamp(inode: 5, modified: t0)
        #expect(BuildFreshness.isStale(launched: s, current: BinaryStamp(inode: 5, modified: t0 + 1)))
    }
    @Test func missingFileIsStale() {
        #expect(BuildFreshness.isStale(launched: BinaryStamp(inode: 5, modified: t0), current: nil))
    }
    @Test func relauncherKeepsInputsOutOfScript() {
        let path = "/Apps/My \"True\"; rm -rf ~/True.app"
        let a = BuildFreshness.relauncherArguments(pid: 42, bundlePath: path)
        #expect(a.count == 5)
        #expect(a[0] == "-c" && a[2] == "sh" && a[3] == "42" && a[4] == path)
        #expect(!a[1].contains("42") && !a[1].contains("rm -rf") && !a[1].contains("open -n"))
        #expect(a[1].contains("kill -0 \"$1\"") && a[1].contains("/usr/bin/open \"$2\""))
    }
    @Test func warningWording() {
        #expect(BuildFreshness.workingWarning(0) == nil)
        #expect(BuildFreshness.workingWarning(1)?.hasPrefix("1 agent is working.") == true)
        #expect(BuildFreshness.workingWarning(3)?.hasPrefix("3 agents are working.") == true)
    }
    @Test func statReadsRealFile() {
        #expect(BinaryStamp.read(URL(fileURLWithPath: "/bin/sh")) != nil)
        #expect(BinaryStamp.read(URL(fileURLWithPath: "/nonexistent/x")) == nil)
    }
}
