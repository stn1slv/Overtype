# Application Compatibility

Because Overtype depends on the macOS Accessibility API (AX) to read and manipulate text natively, it works seamlessly with most native applications but may encounter friction with heavily sandboxed, non-standard, or cross-platform web wrappers that do not expose text fields correctly to VoiceOver and AX systems.

## Supported Applications

- **Native Cocoa Apps**: Apple Notes, Mail, Pages, Messages, Safari, Xcode
- **Electron Apps (with standard AX bindings)**: Slack, Visual Studio Code
- **Chromium Apps**: Google Chrome, Microsoft Edge, Microsoft Teams (PWA / New version)
- **Web Browsers**: Text areas and rich-text editors inside standard browsers.

## Unsupported / Problematic Applications

- **Terminal Emulators**: iTerm2, Terminal.app, Alacritty. (Terminals don't select and manage text via standard macOS AX text ranges).
- **Custom JVM Apps**: Some legacy Java GUI applications.
- **Remote Desktop Clients**: Citrix Workspace, Microsoft Remote Desktop (the text input occurs on a remote host, so AX reading won't capture local text).

## Troubleshooting

If an application is rejecting input:
1. Ensure the app has active focus.
2. Ensure you have granted Accessibility permission in System Settings.
3. Try increasing `typingDelayMs` in `config.json` if characters are being dropped during insertion (especially common in heavily-scripted web rich-text editors like Google Docs).
