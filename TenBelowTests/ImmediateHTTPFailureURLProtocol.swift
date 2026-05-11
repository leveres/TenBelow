//
//  ImmediateHTTPFailureURLProtocol.swift
//  TenBelowTests
//
//  Ephemeral `URLSession` + this stub avoids real network I/O in unit tests.
//

import Foundation

/// Responds immediately with a non-2xx status so `URLSession.decode` fails without hitting the wire.
final class ImmediateHTTPFailureURLProtocol: URLProtocol {
    static var statusCode: Int = 503

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
