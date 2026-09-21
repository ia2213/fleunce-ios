import XCTest
@testable import FleunceCore

final class ProviderFailureTests: XCTestCase {
    func testCreditAndTemporaryLimitsGiveDifferentRecoveryAdvice() {
        let quota = ProviderFailure(status: 429, body: Data(#"{"error":{"code":"insufficient_quota","message":"quota reached"}}"#.utf8), reference: "req_support")
        let rate = ProviderFailure(status: 429, body: Data(#"{"error":{"code":"rate_limit_exceeded"}}"#.utf8))
        XCTAssertEqual(quota.kind, .quota)
        XCTAssertEqual(rate.kind, .rateLimit)
        XCTAssertTrue(quota.errorDescription!.contains("quota"))
        XCTAssertTrue(rate.errorDescription!.contains("wait"))
    }
    func testMalformedAndUntrustedProviderDetailsStayOutOfTheInterface() {
        for body in ["not json", String(repeating: "x", count: 16_385)] {
            let error = ProviderFailure(status: 503, body: Data(body.utf8), reference: "private\nheader")
            XCTAssertEqual(error.kind, .unavailable)
            XCTAssertNil(error.code); XCTAssertNil(error.reference)
        }
        XCTAssertEqual(ProviderFailure(status: 401, body: Data(#"{"error":{"code":"insufficient_quota"}}"#.utf8)).kind, .authentication)
        XCTAssertEqual(ProviderFailure(status: 403).kind, .modelAccess)
    }
}
