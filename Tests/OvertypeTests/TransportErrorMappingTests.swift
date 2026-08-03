import XCTest

@testable import Overtype

final class TransportErrorMappingTests: XCTestCase {

  func testCancellationErrorMapsToCancelled() {
    let mapped = ProviderError.mapTransportError(CancellationError())
    guard case .cancelled = mapped else {
      return XCTFail("expected cancelled, got \(mapped)")
    }
  }

  func testURLErrorCancelledMapsToCancelled() {
    let mapped = ProviderError.mapTransportError(URLError(.cancelled))
    guard case .cancelled = mapped else {
      return XCTFail("expected cancelled, got \(mapped)")
    }
  }

  func testURLErrorTimedOutMapsToTimeout() {
    let mapped = ProviderError.mapTransportError(URLError(.timedOut))
    guard case .timeout = mapped else {
      return XCTFail("expected timeout, got \(mapped)")
    }
  }

  func testOtherURLErrorMapsToNetworkError() {
    let mapped = ProviderError.mapTransportError(URLError(.notConnectedToInternet))
    guard case .networkError = mapped else {
      return XCTFail("expected networkError, got \(mapped)")
    }
  }

  func testUnknownErrorMapsToNetworkError() {
    struct SomeError: Error {}
    let mapped = ProviderError.mapTransportError(SomeError())
    guard case .networkError = mapped else {
      return XCTFail("expected networkError, got \(mapped)")
    }
  }
}
