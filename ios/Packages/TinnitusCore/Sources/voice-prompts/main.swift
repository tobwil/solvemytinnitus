// Prints every spoken phrase as JSON for the voice generator:
// swift run --package-path ios/Packages/TinnitusCore voice-prompts > prompts.json
import Foundation
import TinnitusCore

let items = VoicePrompts.all.map { ["key": VoicePrompts.key($0), "text": $0, "spoken": VoicePrompts.spoken($0)] }
let data = try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
FileHandle.standardOutput.write(data)
print()
