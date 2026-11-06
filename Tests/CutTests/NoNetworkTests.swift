import Foundation
import Testing
@testable import CutKit

/// Runs real network tools under the exact profile Cut applies to itself at launch.
@Suite struct NoNetworkTests {
    func run(_ tool: String, _ args: [String]) throws -> (status: Int32, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        p.arguments = ["-p", NoNetwork.profile, tool] + args
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    @Test func tcpToAnIPIsRefused() throws {
        let r = try run("/usr/bin/nc", ["-z", "-w", "3", "1.1.1.1", "443"])
        #expect(r.status != 0)
    }

    @Test func httpsIsRefused() throws {
        let r = try run("/usr/bin/curl", ["-sS", "-m", "5", "https://1.1.1.1"])
        #expect(r.status != 0)
        #expect(r.err.contains("not permitted") || r.err.contains("Couldn't connect") || r.err.contains("Failed"))
    }

    @Test func dnsIsRefused() throws {
        let r = try run("/usr/bin/dscacheutil", ["-q", "host", "-a", "name", "apple.com"])
        // dscacheutil exits 0 either way; blocked means no address came back.
        #expect(!r.err.contains("ip_address"))
        let out = try run("/usr/bin/host", ["-W", "2", "apple.com"])
        #expect(out.status != 0)
    }

    @Test func localFilesStillWork() throws {
        let r = try run("/bin/ls", ["/Applications"])
        #expect(r.status == 0)
    }
}
