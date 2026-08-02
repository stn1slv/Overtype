import Cocoa

public protocol FeedbackPresenting {
  func showLoading(message: String)
  func showError(message: String)
  func hide()
}

public class FeedbackPresenter: FeedbackPresenting {
  public static let shared = FeedbackPresenter()

  private var hudWindowController: NSWindowController?
  private var hudView: HUDAppKitView?
  private var hideWorkItem: DispatchWorkItem?

  private init() {}

  public func showLoading(message: String) {
    DispatchQueue.main.async {
      self.hideWorkItem?.cancel()
      self.hideWorkItem = nil
      self.display(message: message, isError: false)
    }
  }

  public func showError(message: String) {
    DispatchQueue.main.async {
      self.hideWorkItem?.cancel()

      self.display(message: message, isError: true)

      let workItem = DispatchWorkItem { [weak self] in
        self?.hide()
      }
      self.hideWorkItem = workItem

      // Auto-hide error after 3 seconds safely using a cancellable work item
      DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }
  }

  public func hide() {
    DispatchQueue.main.async {
      self.hideWorkItem?.cancel()
      self.hideWorkItem = nil
      self.hudWindowController?.close()
      self.hudWindowController = nil
      self.hudView = nil
    }
  }

  private func display(message: String, isError: Bool) {
    if hudWindowController == nil {
      let panel = HUDPanel(
        contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
        styleMask: [.nonactivatingPanel, .hudWindow, .utilityWindow],
        backing: .buffered,
        defer: false
      )

      let view = HUDAppKitView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
      panel.contentView = view
      panel.center()

      // Position near bottom of screen
      if let screen = NSScreen.main {
        let frame = panel.frame
        let newOrigin = NSPoint(x: screen.frame.midX - frame.width / 2, y: screen.frame.minY + 100)
        panel.setFrameOrigin(newOrigin)
      }

      hudView = view
      hudWindowController = NSWindowController(window: panel)
    }

    hudView?.update(message: message, isError: isError)
    hudWindowController?.showWindow(nil)
  }
}

public class HUDPanel: NSPanel {
  public override var canBecomeKey: Bool {
    // Important: Return false so we don't steal focus from the target app!
    return false
  }

  public override var canBecomeMain: Bool {
    return false
  }
}

class HUDAppKitView: NSView {
  private let spinner = NSProgressIndicator()
  private let errorIcon = NSImageView()
  private let label = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupViews()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupViews() {
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
    layer?.cornerRadius = 12

    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.translatesAutoresizingMaskIntoConstraints = false
    addSubview(spinner)

    errorIcon.image = NSImage(
      systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")
    errorIcon.contentTintColor = .systemYellow
    errorIcon.imageScaling = .scaleProportionallyUpOrDown
    errorIcon.translatesAutoresizingMaskIntoConstraints = false
    addSubview(errorIcon)

    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textColor = .white
    label.backgroundColor = .clear
    label.isBezeled = false
    label.isEditable = false
    label.isSelectable = false
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)

    NSLayoutConstraint.activate([
      // Spinner constraints
      spinner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
      spinner.widthAnchor.constraint(equalToConstant: 16),
      spinner.heightAnchor.constraint(equalToConstant: 16),

      // ErrorIcon constraints (same frame as spinner)
      errorIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      errorIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
      errorIcon.widthAnchor.constraint(equalToConstant: 16),
      errorIcon.heightAnchor.constraint(equalToConstant: 16),

      // Label constraints
      label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 12),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  func update(message: String, isError: Bool) {
    label.stringValue = message
    if isError {
      spinner.stopAnimation(nil)
      spinner.isHidden = true
      errorIcon.isHidden = false
    } else {
      errorIcon.isHidden = true
      spinner.isHidden = false
      spinner.startAnimation(nil)
    }
  }
}
