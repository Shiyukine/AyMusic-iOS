//
//  PersistedCookie.swift
//  AyMusic
//
//  Created by Shiyukine on 02/07/2026.
//


import Foundation
import WebKit

struct PersistedCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let isSecure: Bool
    let sameSitePolicy: String?

    init(from cookie: HTTPCookie) {
        name            = cookie.name
        value           = cookie.value
        domain          = cookie.domain
        path            = cookie.path
        isSecure        = cookie.isSecure
        sameSitePolicy  = cookie.sameSitePolicy?.rawValue
    }

    func toHTTPCookie() -> HTTPCookie? {
        var props: [HTTPCookiePropertyKey: Any] = [
            .name:    name,
            .value:   value,
            .domain:  domain,
            .path:    path,
            .discard: "TRUE"  // restores it as a session cookie (no expiry)
        ]
        if isSecure {
            props[.secure] = "TRUE"
        }
        if let ssp = sameSitePolicy {
            props[.sameSitePolicy] = HTTPCookieStringPolicy(rawValue: ssp)
        }
        return HTTPCookie(properties: props)
    }
}