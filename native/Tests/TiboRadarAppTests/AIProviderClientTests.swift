import Foundation
import XCTest

@testable import TiboRadarApp

private final class AIURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler:
    ((URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.unknown))
      return
    }
    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

final class AIProviderClientTests: XCTestCase {
  override func tearDown() {
    AIURLProtocol.handler = nil
    super.tearDown()
  }

  func testQwenEnablesSearchAndParsesSharedSchema() async throws {
    var capturedRequest: URLRequest?
    var capturedBody: Data?
    AIURLProtocol.handler = { request in
      capturedRequest = request
      capturedBody = Self.bodyData(from: request)
      return (Self.response(for: request, status: 200), Self.successBody())
    }

    let analysis = try await client().analyze(
      context: "{\"recent_tibo_feed\":[]}",
      configuration: AIConfiguration(provider: .qwen, model: "qwen-plus"),
      apiKey: "test-qwen-key"
    )
    let body = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: XCTUnwrap(capturedBody))
        as? [String: Any]
    )

    XCTAssertEqual(capturedRequest?.url, AIProvider.qwen.endpoint)
    XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-qwen-key")
    XCTAssertEqual(body["enable_search"] as? Bool, true)
    XCTAssertEqual(body["model"] as? String, "qwen-plus")
    XCTAssertFalse(String(data: capturedBody ?? Data(), encoding: .utf8)?.contains("test-qwen-key") == true)
    XCTAssertEqual(analysis.globalSignal, .weak)
    let requestText = String(data: capturedBody ?? Data(), encoding: .utf8) ?? ""
    XCTAssertFalse(requestText.contains("global_24h"))
    XCTAssertTrue(requestText.contains("不得估算或输出任何百分比"))
  }

  func testDeepSeekUsesCollectedSourcesWithoutClaimingSearch() async throws {
    var capturedRequest: URLRequest?
    var capturedBody: Data?
    AIURLProtocol.handler = { request in
      capturedRequest = request
      capturedBody = Self.bodyData(from: request)
      return (Self.response(for: request, status: 200), Self.successBody())
    }

    _ = try await client().analyze(
      context: "{\"recent_tibo_feed\":[]}",
      configuration: AIConfiguration(provider: .deepSeek, model: "deepseek-flash"),
      apiKey: "test-deepseek-key"
    )
    let body = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: XCTUnwrap(capturedBody))
        as? [String: Any]
    )

    XCTAssertEqual(capturedRequest?.url, AIProvider.deepSeek.endpoint)
    XCTAssertNil(body["enable_search"])
    XCTAssertNotNil(body["thinking"])
  }

  func testUnauthorizedResponseIsReportedWithoutServerBodyLeak() async {
    AIURLProtocol.handler = { request in
      let data = Data("{\"error\":{\"message\":\"bad key\"}}".utf8)
      return (Self.response(for: request, status: 401), data)
    }

    do {
      _ = try await client().analyze(
        context: "{}",
        configuration: AIConfiguration(provider: .qwen, model: "qwen-plus"),
        apiKey: "wrong-key"
      )
      XCTFail("Expected authorization error")
    } catch {
      XCTAssertEqual(error as? AIProviderError, .unauthorized)
    }
  }

  private func client() -> AIProviderClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AIURLProtocol.self]
    return AIProviderClient(session: URLSession(configuration: configuration))
  }

  private static func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
    HTTPURLResponse(
      url: request.url!,
      statusCode: status,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
  }

  private static func successBody() -> Data {
    let analysis: [String: Any] = [
      "global_signal": "weak",
      "banked_signal": "none",
      "affected_user_signal": NSNull(),
      "analysis_note": "只有间接暗示，没有明确预告",
      "likely_window": "无法可靠判断",
      "summary": "目前没有明确预告",
      "evidence": [],
    ]
    let analysisData = try! JSONSerialization.data(withJSONObject: analysis)
    let content = String(data: analysisData, encoding: .utf8)!
    let response: [String: Any] = [
      "choices": [["message": ["role": "assistant", "content": content]]]
    ]
    return try! JSONSerialization.data(withJSONObject: response)
  }

  private static func bodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }
}
