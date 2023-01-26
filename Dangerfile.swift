import Danger
import DangerSwiftCoverage
import Foundation

let danger = Danger()

coverage()
changedFiles()

func changedFiles() {
    message("Edited \(danger.git.modifiedFiles.count) files")
    message("Created \(danger.git.createdFiles.count) files")
}

func coverage() {
    guard let xcresult = ProcessInfo.processInfo.environment["$BITRISE_DEPLOY_DIR"]?.escapeString() else {
        fail("Could not get the $BITRISE_DEPLOY_DIR to generage code coverage")
        return
    }

    Coverage.xcodeBuildCoverage(
        .xcresultBundle(xcresult),
        minimumCoverage: 50
    )
}

extension String {
    // Helper function to escape (iOS) in our file name for xcov.
    func escapeString() -> String {
        var newString = self.replacingOccurrences(of: "(", with: "\\(")
        newString = newString.replacingOccurrences(of: ")", with: "\\)")
        newString = newString.replacingOccurrences(of: " ", with: "\\ ")
        return newString
    }
}
