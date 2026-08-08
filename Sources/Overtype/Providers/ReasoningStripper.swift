import Foundation

/// Strips model reasoning ("scratch work") from the START of an answer.
///
/// Shared by the providers whose response text can carry inline reasoning
/// markers: `OllamaProvider` (feature 008, FR-009 layer 2) and
/// `OpenAICompatibleProvider` (feature 009, finding H5 — the `openai` kind
/// points at arbitrary servers, LM Studio, vLLM, and DeepSeek-style
/// deployments included). Gemini and Anthropic filter reasoning STRUCTURALLY
/// (`thought` flag / `text`-block allow-list) and do not use this.
/// Deliberately not part of `ResponseSanitizer`, which runs for all four
/// backends; the trade-offs below are provider-response-specific.
enum ReasoningStripper {

  /// Removes a reasoning block from the START of the answer text.
  ///
  /// Only a block at the very start is removed. Reasoning is emitted before the
  /// answer, so that is where it occurs, and the narrow rule cannot swallow a
  /// legitimate `<think>` in the middle of text the user asked Overtype to
  /// rewrite. An opening marker with no closing match yields an empty string,
  /// which callers turn into `.emptyResponse`: failing visibly beats writing
  /// model scratch work into the document.
  /// Strips every *consecutive* leading block, not just the first: a model that
  /// emits two reasoning blocks back to back would otherwise leave the second
  /// one in the user's document, which is the exact failure this guards
  /// against. The loop terminates because each pass removes a non-empty prefix.
  static func stripLeadingBlock(_ text: String) -> String {
    var current = text.trimmingCharacters(in: .whitespacesAndNewlines)

    var strippedOne = true
    while strippedOne {
      strippedOne = false

      for tag in ["think", "thinking"] {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard current.lowercased().hasPrefix(open) else { continue }

        guard let closeRange = current.range(of: close, options: .caseInsensitive) else {
          // Unterminated: everything that follows is reasoning.
          return ""
        }
        current = String(current[closeRange.upperBound...])
          .trimmingCharacters(in: .whitespacesAndNewlines)
        strippedOne = true
        break
      }
    }

    return stripOrphanPrefix(current)
  }

  /// Removes reasoning that has a CLOSING marker but no opening one.
  ///
  /// This shape is not hypothetical and is arguably the more common of the two.
  /// DeepSeek-R1's chat template appends `<think>` to the *prompt*, so the
  /// completion begins with bare reasoning and ends with a lone `</think>`:
  ///
  ///     "Okay, the subject is singular...\n</think>\nThe cat is sleeping."
  ///
  /// Ollama usually catches it upstream, because it splits such models' output
  /// into `message.thinking`. But that split depends on the served model
  /// declaring the thinking capability, and a custom Modelfile or a community
  /// GGUF may not — in which case the raw completion arrives in the content
  /// field and, without this rule, model scratch work would be typed over the
  /// user's selection. OpenAI-compatible servers have no upstream split at all.
  ///
  /// ACCEPTED TRADEOFF, do not "simplify" without reading this: text a user
  /// legitimately selected could contain a closing marker with its opening tag
  /// outside the selection (someone editing prose *about* this markup). That
  /// text would be cut. The rule is deliberately narrowed to make this as rare
  /// as possible — it fires only when NO opening marker precedes the closing
  /// one, so a properly paired block anywhere in the text is left alone — and
  /// the trade was made toward cutting rare prose over writing model reasoning
  /// into a document, because reasoning leakage is silent and unbounded while
  /// this is visible in the result.
  static func stripOrphanPrefix(_ text: String) -> String {
    for tag in ["think", "thinking"] {
      let open = "<\(tag)>"
      let close = "</\(tag)>"

      guard let closeRange = text.range(of: close, options: .caseInsensitive) else { continue }

      // A matched pair is not the orphan shape; leave it to the caller's rules.
      if let openRange = text.range(of: open, options: .caseInsensitive),
        openRange.lowerBound < closeRange.lowerBound
      {
        continue
      }

      return String(text[closeRange.upperBound...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return text
  }
}
