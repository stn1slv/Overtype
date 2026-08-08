import ApplicationServices
import XCTest

@testable import Overtype

/// H1 (review follow-up): drives `ActionEngine.readWithHardTimeout` through its
/// `SelectionReading` seam. Creating an AXUIElement handle needs no
/// Accessibility permission; no AX call is ever made on it here.
final class ReadTimeoutTests: XCTestCase {

  private struct ImmediateReader: SelectionReading {
    func readSelection() throws -> Selection {
      Selection(text: "hello", element: AXUIElementCreateSystemWide(), pid: 42)
    }
  }

  /// Blocks without observing cancellation, like a raw AX call would; kept
  /// short so the group's post-timeout wait stays test-friendly.
  private struct SlowReader: SelectionReading {
    func readSelection() throws -> Selection {
      Thread.sleep(forTimeInterval: 0.5)
      return Selection(text: "late", element: AXUIElementCreateSystemWide(), pid: 42)
    }
  }

  /// Mirrors the production readers, which hit a cancellation checkpoint at
  /// every bounded AX call.
  private struct CancellationAwareBlockedReader: SelectionReading {
    func readSelection() throws -> Selection {
      while true {
        try Task.checkCancellation()
        Thread.sleep(forTimeInterval: 0.02)
      }
    }
  }

  func testFastReadReturnsSelection() async throws {
    let selection = try await ActionEngine.readWithHardTimeout(
      seconds: 5, appName: "TestApp", using: ImmediateReader())
    XCTAssertEqual(selection.text, "hello")
    XCTAssertEqual(selection.pid, 42)
  }

  func testTimeoutThrowsTypedErrorNamingTheApp() async {
    do {
      _ = try await ActionEngine.readWithHardTimeout(
        seconds: 0.05, appName: "FrozenApp", using: SlowReader())
      XCTFail("expected readTimedOut")
    } catch Overtype.AXError.readTimedOut(let appName) {
      XCTAssertEqual(appName, "FrozenApp")
    } catch {
      XCTFail("expected readTimedOut, got \(error)")
    }
  }

  func testTimeoutReturnsPromptlyWithCancellationAwareReader() async {
    // After the timeout fires, the group waits only until the cancelled read
    // child observes cancellation; with checkpointed readers that is bounded.
    let start = Date()
    do {
      _ = try await ActionEngine.readWithHardTimeout(
        seconds: 0.05, appName: nil, using: CancellationAwareBlockedReader())
      XCTFail("expected readTimedOut")
    } catch Overtype.AXError.readTimedOut(let appName) {
      XCTAssertNil(appName)
    } catch {
      XCTFail("expected readTimedOut, got \(error)")
    }
    XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
  }

  func testExternalCancellationSurfacesAsCancellationError() async {
    let task = Task {
      try await ActionEngine.readWithHardTimeout(
        seconds: 5, appName: nil, using: CancellationAwareBlockedReader())
    }
    try? await Task.sleep(nanoseconds: 50_000_000)
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("expected cancellation")
    } catch is CancellationError {
      // Escape maps to the engine's quiet-cancel path, not to a timeout error.
    } catch {
      XCTFail("expected CancellationError, got \(error)")
    }
  }
}
