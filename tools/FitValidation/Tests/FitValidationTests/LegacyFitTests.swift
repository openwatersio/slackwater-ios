import XCTest
@testable import fit_validation

final class LegacyFitTests: XCTestCase {
    func testOldFitterPhasesAreConvertedForTheCurrentEngine() {
        let original = [FitOut.Con(name: "M3", amplitude: 0.15, phase: 30),
                        FitOut.Con(name: "M2", amplitude: 1, phase: 45),
                        FitOut.Con(name: "S3", amplitude: 0.2, phase: 250),
                        FitOut.Con(name: "M7", amplitude: 0.1, phase: 180)]
        let converted = engineConstituents(original)
        XCTAssertEqual(converted.map(\.phase), [210, 45, 70, 0])
        XCTAssertEqual(converted.map(\.amplitude), [0.15, 1, 0.2, 0.1])
    }
}
