# Quickstart & Validation Guide

This guide outlines how to manually validate that Overtype (Overtype) functions according to the `BUILD_SPEC.md` and Constitution.

## Prerequisites
- macOS 13 Ventura or newer
- Xcode 15 or later for building
- A valid API key for OpenAI, Anthropic, OR a local instance of Ollama running on `localhost:11434`.

## Build & Run
1. Open the Swift package/project.
2. Build the application target.
3. Because the application requires Accessibility permissions, it must be run as a bundled `.app`.
4. Run the `./scripts/build-app.sh` script to package and ad-hoc sign the application.
5. Launch the generated `Overtype.app`.

## Validation Scenarios

### 1. Permission Grant
- On first launch, the app should display a permission window requesting Accessibility access.
- Click the button to open System Settings, grant permission, and verify the app detects the permission without restarting.

### 2. Clipboard Isolation (M2 Milestone)
- Copy the text `CLIPBOARD_SAFE` to your system clipboard (`Cmd+C`).
- Open **Microsoft Teams** or **TextEdit**.
- Type a sentence and select it.
- Trigger the "Fix grammar" shortcut (e.g., `Ctrl+Option+Cmd+G`).
- Verify the text is replaced.
- Paste (`Cmd+V`) and verify that `CLIPBOARD_SAFE` is pasted, proving the clipboard was not touched.

### 3. Settings & Extensibility (M6 Milestone)
- Click the Menu Bar icon and open "Settings...".
- Go to the Actions tab and duplicate the "Fix grammar" action.
- Change the prompt to "Make this uppercase" and save it with a new shortcut.
- Select text in any app, trigger the new shortcut, and verify it converts the text to uppercase immediately.

### 4. Cancellation (M5 Milestone)
- Select text and trigger an AI action.
- Immediately press the `Escape` key while the HUD indicates it is busy.
- Verify the action aborts, the HUD disappears, and the selected text remains unmodified.
