import XCTest
@testable import FlyyLinkKit

/// Mirrors LicenceTests.cs. The tokens were signed by the licence server's code with a test key.
final class LicenceTests: XCTestCase {
    private static let publicKey = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEncVafPUhUOuV2pFFsl3AV3asVMwIby4RkyUx9aA4H6rua20jBexnHB4GmtFK2KBcQE01LOdbR00l6ttq4ep/ig=="
    private static let licenceFixture = "eyJ2IjoxLCJraW5kIjoibGljZW5jZSIsIm1hY2hpbmUiOiJtMSIsImVtYWlsIjoiYnV5ZXJAZXhhbXBsZS5jb20iLCJpc3N1ZWQiOjEwMDAsInJlbmV3IjoyMDAwLCJleHBpcmVzIjozMDAwfQ.e6G63Vg1icZgrAkvoXYq0QMxJpBU4QGP0XMlmELrk-ITRSOjgGeIOjdzvGKebc33nWoBtOr0rJsZYpHSL0C14w"
    private static let trialFixture = "eyJ2IjoxLCJraW5kIjoidHJpYWwiLCJtYWNoaW5lIjoibTEiLCJpc3N1ZWQiOjEwMDAsInJlbmV3Ijo1MDAwLCJleHBpcmVzIjo1MDAwfQ.p_7sfjcfFzFUMyBWR6VaSjy8ux7QFhPTc0EtkjZewOA8-iAMa-Kanv_SSsC8M8um3Nf86iZBUyq41CdmO1zikQ"

    private let firstLaunch = Date(timeIntervalSince1970: 1000)

    func testReadsASignedToken() {
        let claims = LicenceToken.verify(Self.licenceFixture, publicKey: Self.publicKey)

        XCTAssertEqual(claims, LicenceClaims(kind: "licence", machine: "m1", email: "buyer@example.com", issued: 1000, renew: 2000, expires: 3000))
    }

    func testRefusesAChangedToken() {
        let trialBody = Self.trialFixture.split(separator: ".")[0]
        let licenceSignature = Self.licenceFixture.split(separator: ".")[1]

        XCTAssertNil(LicenceToken.verify("\(trialBody).\(licenceSignature)", publicKey: Self.publicKey))
        XCTAssertNil(LicenceToken.verify("not a token", publicKey: Self.publicKey))
    }

    func testLicensedUntilItExpires() {
        let record = LicenceRecord(licenceToken: Self.licenceFixture, firstLaunch: firstLaunch)

        XCTAssertEqual(evaluate(record, at: 1500), .licensed(email: "buyer@example.com", shouldRenew: false))
        XCTAssertEqual(evaluate(record, at: 2500), .licensed(email: "buyer@example.com", shouldRenew: true))
        XCTAssertEqual(evaluate(record, at: 3000), .locked(.offline))
    }

    func testTokenForAnotherComputerDoesNotCount() {
        let record = LicenceRecord(licenceToken: Self.licenceFixture, trialToken: Self.trialFixture, firstLaunch: firstLaunch)

        XCTAssertEqual(LicenceRules.evaluate(record, machine: "m2", publicKey: Self.publicKey, now: Date(timeIntervalSince1970: 1500)), .trial(daysLeft: LicenceRules.trialDays))
    }

    func testTrialCountsDownThenLocks() {
        let record = LicenceRecord(trialToken: Self.trialFixture, firstLaunch: firstLaunch)

        XCTAssertEqual(evaluate(record, at: 4000), .trial(daysLeft: 1))
        XCTAssertEqual(evaluate(record, at: 5000), .locked(.trialOver))
    }

    func testOfflineTrialRunsFromFirstLaunch() {
        let record = LicenceRecord(firstLaunch: firstLaunch)

        XCTAssertEqual(evaluate(record, at: 1001), .trial(daysLeft: 14))
        XCTAssertEqual(evaluate(record, at: 1000 + 13 * 86400 + 1), .trial(daysLeft: 1))
        XCTAssertEqual(evaluate(record, at: 1000 + 14 * 86400), .locked(.offline))
    }

    func testServerLockWinsOverTheTrial() {
        let record = LicenceRecord(trialToken: Self.trialFixture, firstLaunch: firstLaunch, serverLock: .removed)

        XCTAssertEqual(evaluate(record, at: 1500), .locked(.removed))
    }

    func testNoKeyMeansUnlimited() {
        XCTAssertEqual(LicenceRules.evaluate(LicenceRecord(firstLaunch: firstLaunch), machine: "m1", publicKey: nil, now: Date(timeIntervalSince1970: 0)), .unlimited)
    }

    func testMachineIdIsAStableHash() {
        XCTAssertEqual(MachineId.from(" ABC "), MachineId.from("abc"))
        XCTAssertEqual(MachineId.from("abc"), "d2411e14a3705cc79bff7bf923a5655a0a23014b45072915c3e38e9046f4d34a")
    }

    private func evaluate(_ record: LicenceRecord, at seconds: TimeInterval) -> LicenceStatus {
        LicenceRules.evaluate(record, machine: "m1", publicKey: Self.publicKey, now: Date(timeIntervalSince1970: seconds))
    }
}
