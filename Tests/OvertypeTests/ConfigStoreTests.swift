import XCTest
@testable import Overtype

final class ConfigStoreTests: XCTestCase {
    
    func testDefaultConfigIsValidJSON() {
        let json = DefaultConfig.defaultConfigJSON
        let data = json.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        XCTAssertNoThrow(try decoder.decode(AppConfig.self, from: data))
    }
    
    func testDefaultConfigContainsGrammarAction() {
        let config = DefaultConfig.defaultConfig
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.actions.first?.id, "fix-grammar")
        XCTAssertEqual(config?.actions.first?.providerID, "openai")
    }
}
