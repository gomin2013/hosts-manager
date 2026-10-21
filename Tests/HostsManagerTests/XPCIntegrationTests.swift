import XCTest
import Shared
@testable import HostsManagerApp
@testable import HostsManagerHelper

/// App ↔ helper over real XPC: `HelperService` behind an anonymous in-process listener, writing a temp file,
/// so requests / replies / NSErrors go through NSXPC serialization exactly as in production (minus launchd + root).
@MainActor
final class XPCIntegrationTests: XCTestCase {
    /// Production delegate minus the code-signing check (the test runner isn't the app).
    private final class TestDelegate: NSObject, NSXPCListenerDelegate {
        let writer: HostsWriter
        init(writer: HostsWriter) { self.writer = writer }

        func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
            connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
            connection.exportedObject = HelperService(writer: writer)
            connection.resume()
            return true
        }
    }

    private var root: URL!
    private var hostsURL: URL!
    private var listener: NSXPCListener!
    private var delegate: TestDelegate!
    private var xpc: XPCService!

    private let original = """
    ##
    # Host Database
    ##
    127.0.0.1\tlocalhost

    # Dev
    127.0.0.1\tapi.test

    """

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("XPCIntegrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        hostsURL = root.appendingPathComponent("hosts")
        try original.write(to: hostsURL, atomically: true, encoding: .utf8)

        delegate = TestDelegate(writer: HostsWriter(
            hostsURL: hostsURL, backupsURL: root.appendingPathComponent("Backups"), flushDNS: {}
        ))
        listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        xpc = XPCService(endpoint: listener.endpoint)
    }

    override func tearDown() async throws {
        await xpc.invalidate()
        listener.invalidate()
        try? FileManager.default.removeItem(at: root)
    }

    private var contents: String { (try? String(contentsOf: hostsURL, encoding: .utf8)) ?? "" }

    // MARK: - XPCService ↔ HelperService

    func testWriteRoundTripAndVersion() async throws {
        let hash = try Data(contentsOf: hostsURL).sha256Hex
        try await xpc.writeHosts("127.0.0.1 localhost\n", expectedSHA256: hash)
        XCTAssertEqual(contents, "127.0.0.1 localhost\n")
        let version = try await xpc.version()
        XCTAssertFalse(version.isEmpty)
    }

    func testHelperErrorsSurviveXPC() async {
        do {
            try await xpc.writeHosts("127.0.0.1 localhost\n", expectedSHA256: "stale")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? HelperError, .staleFile)
        }
    }

    /// Like the production delegate when the code-signing requirement doesn't match: connection refused.
    private final class RejectingDelegate: NSObject, NSXPCListenerDelegate {
        func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
            false
        }
    }

    func testRejectedConnectionIsConnectionFailed() async {
        let rejecting = RejectingDelegate()
        let refusing = NSXPCListener.anonymous()
        refusing.delegate = rejecting
        refusing.resume()
        defer { refusing.invalidate() }

        do {
            try await XPCService(endpoint: refusing.endpoint).writeHosts("x", expectedSHA256: "")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? HelperError, .connectionFailed)
        }
    }

    /// Accepts the connection but never answers — what the app sees when launchd won't start an updated helper.
    private final class SilentDelegate: NSObject, NSXPCListenerDelegate, HelperProtocol {
        func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
            connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
            connection.exportedObject = self
            connection.resume()
            return true
        }
        func version(reply: @escaping @Sendable (String) -> Void) {}
        func writeHosts(_ content: String, expectedSHA256: String, reply: @escaping @Sendable (NSError?) -> Void) {}
    }

    func testIsRespondingTellsAWorkingHelperFromASilentOrRejectingOne() async {
        let isWorking = await xpc.isResponding(within: .seconds(2))
        XCTAssertTrue(isWorking)

        let silent = SilentDelegate(), quiet = NSXPCListener.anonymous()
        quiet.delegate = silent
        quiet.resume()
        let rejecting = RejectingDelegate(), refusing = NSXPCListener.anonymous()
        refusing.delegate = rejecting
        refusing.resume()
        defer { quiet.invalidate(); refusing.invalidate() }

        let start = ContinuousClock.now
        let isSilentOK = await XPCService(endpoint: quiet.endpoint).isResponding(within: .milliseconds(300))
        XCTAssertFalse(isSilentOK, "no reply → not responding")
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(5), "the short timeout, not a save's 30 s")
        let isRejectedOK = await XPCService(endpoint: refusing.endpoint).isResponding(within: .seconds(2))
        XCTAssertFalse(isRejectedOK)
    }

    // MARK: - Client pinning (ADR-010)

    func testCDHashMatchesCodesign() throws {
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let hash = try XCTUnwrap(CodeSignature.cdhash(ofAppAt: calculator))

        let codesign = Process()
        let pipe = Pipe()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["-dvvv", calculator.path]
        codesign.standardError = pipe   // codesign prints details on stderr
        try codesign.run()
        codesign.waitUntilExit()
        let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("CDHash=\(hash)"), output)

        XCTAssertEqual(
            HelperListenerDelegate.requirement(forAppAt: calculator),
            "identifier \"com.hostsmanager.app\" and cdhash H\"\(hash)\""
        )
        XCTAssertNil(CodeSignature.cdhash(ofAppAt: URL(fileURLWithPath: "/usr/bin/codesign")))
    }

    /// The production delegate: any client that isn't the pinned app — here the test runner — is refused,
    /// both when a requirement exists (pinned to another app) and when none can be built (fail closed).
    func testProductionDelegateRejectsOtherClients() async {
        for appURL in ["/System/Applications/Calculator.app", "/nonexistent.app"].map(URL.init(fileURLWithPath:)) {
            let delegate = HelperListenerDelegate()
            delegate.appURL = appURL
            let pinned = NSXPCListener.anonymous()
            pinned.delegate = delegate
            pinned.resume()
            do {
                _ = try await XPCService(endpoint: pinned.endpoint).version()
                XCTFail("\(appURL.path): expected the test runner to be rejected")
            } catch {
                XCTAssertEqual(error as? HelperError, .connectionFailed, appURL.path)
            }
            pinned.invalidate()
        }
    }

    // MARK: - HostsViewModel end to end

    func testViewModelLoadToggleAddEditDelete() async throws {
        let vm = HostsViewModel(hostsURL: hostsURL, xpc: xpc)
        XCTAssertEqual(vm.entries.map(\.hostnames), [["localhost"], ["api.test"]])
        XCTAssertEqual(vm.rawText, original, "an untouched file serializes byte-for-byte")

        vm.toggle(vm.entries[1])
        try await waitUntilSaved(vm)
        XCTAssertTrue(contents.contains("# 127.0.0.1\tapi.test\n"))

        vm.beginAdd()
        vm.editor?.ip = "10.0.0.5"
        vm.editor?.hostnamesText = "staging.test"
        vm.editor?.comment = "VPN #1"
        vm.commitEditor()
        try await waitUntilSaved(vm)
        XCTAssertTrue(contents.hasSuffix("## VPN 1\n10.0.0.5\tstaging.test\n"))

        vm.beginEdit(vm.entries[2])
        vm.editor?.hostnamesText = "staging2.test"
        vm.commitEditor()
        try await waitUntilSaved(vm)
        XCTAssertTrue(contents.hasSuffix("## VPN 1\n10.0.0.5\tstaging2.test\n"))

        let section = try XCTUnwrap(vm.filteredRows.first { if case .section = $0 { true } else { false } })
        vm.delete(section)
        try await waitUntilSaved(vm)
        XCTAssertFalse(contents.contains("# Dev"))
        XCTAssertNil(vm.errorMessage)
    }

    func testSystemRowsCannotBeChanged() async throws {
        let vm = HostsViewModel(hostsURL: hostsURL, xpc: xpc)
        let header = try XCTUnwrap(vm.filteredRows.first)
        vm.delete(header)
        vm.toggle(vm.entries[0])
        vm.beginEdit(vm.entries[0])
        XCTAssertFalse(vm.isSaving)
        XCTAssertNil(vm.editor)
        XCTAssertEqual(contents, original)
    }

    func testOutsideEditMakesSaveFailAndReloads() async throws {
        let vm = HostsViewModel(hostsURL: hostsURL, xpc: xpc)
        let outside = original + "10.9.9.9\toutside.test\n"
        try outside.write(to: hostsURL, atomically: true, encoding: .utf8)

        vm.toggle(vm.entries[1])
        try await waitUntilSaved(vm)

        XCTAssertEqual(contents, outside, "the helper refused to overwrite the newer file")
        XCTAssertEqual(vm.errorMessage, localized("err.staleFile"))
        XCTAssertEqual(vm.entries.last?.hostnames, ["outside.test"], "the view model reloaded from disk")
    }

    // MARK: - Feature completion (Phase 3)

    private func makeViewModel() -> HostsViewModel {
        HostsViewModel(hostsURL: hostsURL, backupsURL: root.appendingPathComponent("Backups"),
                       pinsURL: root.appendingPathComponent("pins.json"), xpc: xpc)
    }

    func testAddRenameAndRemoveSection() async throws {
        let vm = makeViewModel()
        vm.addSection()
        try await waitUntilSaved(vm)
        let added = try XCTUnwrap(vm.filteredRows.last)
        XCTAssertEqual(added, .section(id: 7, title: ""))

        vm.renameSection(added, to: "Staging")
        try await waitUntilSaved(vm)
        XCTAssertTrue(contents.hasSuffix("127.0.0.1\tapi.test\n\n# Staging\n"))

        vm.renameSection(try XCTUnwrap(vm.filteredRows.last), to: "")
        try await waitUntilSaved(vm)
        XCTAssertTrue(contents.hasSuffix("127.0.0.1\tapi.test\n\n"))
    }

    func testMoveRowsCarriesTheWholeSection() async throws {
        let vm = makeViewModel()
        vm.moveRows(from: [2], to: 4)  // "# Dev" section below the api.test entry
        try await waitUntilSaved(vm)
        XCTAssertEqual(contents, "##\n# Host Database\n##\n127.0.0.1\tlocalhost\n127.0.0.1\tapi.test\n\n# Dev\n")

        vm.searchText = "api"
        vm.moveRows(from: [0], to: 1)
        XCTAssertFalse(vm.isSaving, "no reordering while searching")
    }

    // rows: 0 header · 1 localhost · 2 §Dev · 3 api · 4 web · 5 §Staging · 6 staging
    private let twoSections = "##\n# Host Database\n##\n127.0.0.1\tlocalhost\n\n# Dev\n127.0.0.1\tapi.test\n"
        + "127.0.0.1\tweb.test\n\n# Staging\n10.0.0.5\tstaging.test\n"

    func testMultiSelectDragMovesRowsTogetherInOrder() async throws {
        try twoSections.write(to: hostsURL, atomically: true, encoding: .utf8)
        let vm = makeViewModel()
        vm.moveRows(from: [3, 4], to: 7)   // api + web below staging
        try await waitUntilSaved(vm)
        XCTAssertTrue(contents.hasSuffix(
            "# Staging\n10.0.0.5\tstaging.test\n127.0.0.1\tapi.test\n127.0.0.1\tweb.test\n"
        ))
        let selected = vm.filteredRows.filter { vm.selection.contains($0.id) }.compactMap { row -> String? in
            if case .entry(_, let entry) = row { entry.hostnames[0] } else { nil }
        }
        XCTAssertEqual(selected, ["api.test", "web.test"], "the moved rows stay selected")
    }

    func testDragMovesASectionWithItsEntry() async throws {
        try twoSections.write(to: hostsURL, atomically: true, encoding: .utf8)
        let vm = makeViewModel()
        vm.moveRows(from: [5, 6], to: 2)   // Staging section + entry above Dev
        try await waitUntilSaved(vm)
        XCTAssertEqual(contents, "##\n# Host Database\n##\n127.0.0.1\tlocalhost\n\n# Staging\n10.0.0.5\tstaging.test\n"
            + "\n# Dev\n127.0.0.1\tapi.test\n127.0.0.1\tweb.test\n")
    }

    func testSelectedSystemRowsDoNotMove() async throws {
        try twoSections.write(to: hostsURL, atomically: true, encoding: .utf8)
        let vm = makeViewModel()
        vm.moveRows(from: [0, 1, 3], to: 7)   // header + localhost + api → only api moves
        try await waitUntilSaved(vm)
        XCTAssertTrue(contents.hasPrefix(
            "##\n# Host Database\n##\n127.0.0.1\tlocalhost\n\n# Dev\n127.0.0.1\tweb.test\n"
        ))
        XCTAssertTrue(contents.hasSuffix("10.0.0.5\tstaging.test\n127.0.0.1\tapi.test\n"))

        vm.moveRows(from: [0, 1], to: 5)      // only system rows → nothing happens
        XCTAssertFalse(vm.isSaving)
    }

    func testImportMergeSkipsDuplicatesAndSystemEntries() async throws {
        let vm = makeViewModel()
        vm.beginImport("127.0.0.1 localhost\n127.0.0.1 api.test\n10.0.0.1 new.test\n")
        XCTAssertEqual(vm.pendingImportCount, 2, "imported localhost is ignored")

        vm.applyImport(replace: false)
        try await waitUntilSaved(vm)
        XCTAssertEqual(contents, original + "10.0.0.1 new.test\n")
    }

    func testImportReplaceKeepsThisMacsSystemLines() async throws {
        let vm = makeViewModel()
        vm.beginImport("##\n# Host Database\n##\n127.0.0.1 localhost\n10.0.0.1 new.test\n")
        vm.applyImport(replace: true)
        try await waitUntilSaved(vm)
        XCTAssertEqual(contents, "##\n# Host Database\n##\n127.0.0.1\tlocalhost\n\n10.0.0.1 new.test\n")
    }

    func testHistoryReadsTheHelpersBackupsAndRestoresThroughIt() async throws {
        let vm = makeViewModel()
        XCTAssertEqual(vm.history.recent.map(\.id), ["current"])

        vm.toggle(vm.entries[1])
        try await waitUntilSaved(vm)
        XCTAssertEqual(vm.history.recent.first?.change, .turnedOff("api.test"))
        XCTAssertEqual(vm.history.recent.last?.text, original, "the backup the helper made")

        vm.restore(try XCTUnwrap(vm.history.recent.last).text)
        try await waitUntilSaved(vm)
        XCTAssertEqual(contents, original)
        XCTAssertEqual(vm.history.recent.count, 3, "the restore is a new step")
        XCTAssertNotNil(vm.history.recent[1].date, "dated by the backup stamp of the save that replaced it")
    }

    func testExportIsByteIdentical() throws {
        let vm = makeViewModel()
        let target = root.appendingPathComponent("exported.txt")
        try vm.export(to: target)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), original)
    }

    // MARK: - Helpers

    private func waitUntilSaved(_ vm: HostsViewModel, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        try await Task.sleep(for: .milliseconds(20))
        while vm.isSaving {
            guard Date() < deadline else { return XCTFail("timed out waiting for save") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
