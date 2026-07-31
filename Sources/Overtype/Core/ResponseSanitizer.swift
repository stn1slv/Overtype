import Foundation

public class ResponseSanitizer {
    
    public init() {}
    
    /// Sanitizes the AI response based on the original selected text
    public func sanitize(response: String, originalText: String) -> String {
        var cleanResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove conversational prefixes if any leaked through despite prompts
        let prefixesToRemove = ["Here is the corrected text:", "Here is the text:", "Sure, here you go:"]
        for prefix in prefixesToRemove {
            if cleanResponse.hasPrefix(prefix) {
                cleanResponse = cleanResponse.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Remove wrapping quotes if the original text did NOT have them,
        // but the AI aggressively added them.
        if !originalText.hasPrefix("\"") && !originalText.hasSuffix("\"") {
            if cleanResponse.hasPrefix("\"") && cleanResponse.hasSuffix("\"") && cleanResponse.count >= 2 {
                cleanResponse = String(cleanResponse.dropFirst().dropLast())
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
        
        return cleanResponse
    }
}
