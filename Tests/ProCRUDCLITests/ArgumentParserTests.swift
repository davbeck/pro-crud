import ProCRUDCore
import Testing
@testable import ProCRUDCLI

@Suite("Argument parser")
struct ArgumentParserTests {
	@Test func reportsReleaseVersion() {
		#expect(ProCRUD.configuration.version == proCRUDVersion)
	}
}
