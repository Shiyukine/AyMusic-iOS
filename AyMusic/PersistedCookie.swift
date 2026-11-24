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
    // Optional so files written by older builds (session-only cookies) still decode
    let expiresDate: Date?
    let isHTTPOnly: Bool?

    init(from cookie: HTTPCookie) {
        name            = cookie.name
        value           = cookie.value
        domain          = cookie.domain
        path            = cookie.path
        isSecure        = cookie.isSecure
        sameSitePolicy  = cookie.sameSitePolicy?.rawValue
        expiresDate     = cookie.isSessionOnly ? nil : cookie.expiresDate
        isHTTPOnly      = cookie.isHTTPOnly
    }

    func toHTTPCookie() -> HTTPCookie? {
        var props: [HTTPCookiePropertyKey: Any] = [
            .name:    name,
            .value:   value,
            .domain:  domain,
            .path:    path
        ]
        if let expiresDate {
            if expiresDate <= Date() { return nil }  // already expired
            props[.expires] = expiresDate
        } else {
            props[.discard] = "TRUE"  // restores it as a session cookie (no expiry)
        }
        if isHTTPOnly == true {
            props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }
        if isSecure {
            props[.secure] = "TRUE"
        }
        if let ssp = sameSitePolicy {
            props[.sameSitePolicy] = HTTPCookieStringPolicy(rawValue: ssp)
        }
        return HTTPCookie(properties: props)
    }
}