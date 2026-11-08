import ProCRUDCore
import Testing
@testable import ProCRUDCLI

@Suite("Argument parser")
struct ArgumentParserTests {
	@Test func reportsBuildVersion() {
		#if DEBUG
			let prefix = "DEBUG "
		#else
			let prefix = ""
		#endif
		#expect(ProCRUD.configuration.version == "\(prefix)\(proCRUDVersion) (\(proCRUDGitCommit))")
	}
}
