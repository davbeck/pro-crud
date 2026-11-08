import Foundation
import PackagePlugin

@main
struct GitVersionPlugin: BuildToolPlugin {
	func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
		let output = context.pluginWorkDirectoryURL.appending(path: "Generated")
		return [.prebuildCommand(
			displayName: "Embed Git commit in CLI version",
			executable: URL(filePath: "/bin/sh"),
			arguments: [
				"-eu", "-c", """
				commit=$(/usr/bin/git -C "$1" rev-parse --short HEAD)
				mkdir -p "$2"
				source="let proCRUDGitCommit = \\"$commit\\""
				if [ ! -f "$2/GitCommit.swift" ] || [ "$(cat "$2/GitCommit.swift")" != "$source" ]; then
				    printf '%s\\n' "$source" > "$2/GitCommit.swift"
				fi
				""",
				"git-version", context.package.directoryURL.path(), output.path(),
			],
			outputFilesDirectory: output,
		)]
	}
}
