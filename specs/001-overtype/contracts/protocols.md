# Internal Contracts: Protocols

The application architecture relies on dependency inversion via Swift protocols to allow modular development, testing, and swapping of AI providers or text writing strategies.

## `ActionRunning`
Orchestrates the end-to-end flow of reading text, fetching AI completions, and writing text back.
```swift
protocol ActionRunning {
    func run(actionID: String) async
}
```

## `SelectionReading`
Encapsulates Accessibility API logic to read text from the frontmost application.
```swift
protocol SelectionReading {
    func readSelection() throws -> Selection
}
```

## `TextWriting`
Encapsulates `CGEvent` and Accessibility API logic to write text back to the target application safely without clipboard usage.
```swift
protocol TextWriting {
    func replaceSelection(_ selection: Selection,
                          with text: String,
                          strategy: WriteStrategy,
                          settings: GeneralConfig) throws
}
```

## `AIProvider`
Standard interface for AI interactions.
```swift
protocol AIProvider {
    var id: String { get }
    func transform(_ request: TransformRequest) async throws -> String
}
```
