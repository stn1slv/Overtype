import Foundation

public class ResponseSanitizer {

  public init() {}

  /// Sanitizes the AI response based on the original selected text.
  /// When `allowNewlines` is false, the result is collapsed to a single line so an
  /// action that declares single-line output (e.g. an inline grammar fix) never
  /// writes multi-line text into the target.
  public func sanitize(response: String, originalText: String, allowNewlines: Bool = true) -> String
  {
    var cleanResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)

    // Remove conversational prefixes if any leaked through despite prompts
    let prefixesToRemove = [
      "Here is the corrected text:", "Here is the text:", "Sure, here you go:",
    ]
    for prefix in prefixesToRemove {
      if cleanResponse.hasPrefix(prefix) {
        cleanResponse = cleanResponse.dropFirst(prefix.count).trimmingCharacters(
          in: .whitespacesAndNewlines)
      }
    }

    // Remove wrapping quotes if the original text did NOT have them,
    // but the AI aggressively added them. Only strip when the interior contains
    // no further double quote: text like `"Hi," he said. "Bye."` starts and ends
    // with a quote yet is not wrapped, and stripping would corrupt it.
    if !originalText.hasPrefix("\"") && !originalText.hasSuffix("\"") {
      if cleanResponse.hasPrefix("\"") && cleanResponse.hasSuffix("\"") && cleanResponse.count >= 2
      {
        let inner = String(cleanResponse.dropFirst().dropLast())
        if !inner.contains("\"") {
          cleanResponse = inner
        }
      }
    }

    // Remove markdown code blocks if the AI decided to format it as code
    if cleanResponse.hasPrefix("```") {
      let lines = cleanResponse.components(separatedBy: .newlines)
      if lines.count >= 2 && lines.last?.hasPrefix("```") == true {
        // Drop the first line (e.g. ```text) and the last line (```)
        let innerLines = lines.dropFirst().dropLast()
        cleanResponse = innerLines.joined(separator: "\n")
      }
    }

    // Enforce single-line output when the action does not allow newlines.
    if !allowNewlines {
      cleanResponse =
        cleanResponse
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    return cleanResponse
  }
}
