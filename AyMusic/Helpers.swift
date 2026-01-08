//
//  Helpers.swift
//  AyMusic
//
//  Created by Shiyukine on 12/31/25.
//

import SwiftUI

// MARK: - Array JSON Helper
extension Array where Element == [String: String] {
    var jsonString: String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: self, options: []) else {
            return nil
        }
        return String(data: jsonData, encoding: .utf8)
    }
}

extension URLRequest {

    func bodySteamAsJSON() -> Any? {

        guard let bodyStream = self.httpBodyStream else {
            return nil
        }

        bodyStream.open()

        // Will read 16 chars per iteration. Can use bigger buffer if needed
        let bufferSize: Int = 16

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)

        var dat = Data()

        while bodyStream.hasBytesAvailable {

            let readDat = bodyStream.read(buffer, maxLength: bufferSize)
            dat.append(buffer, count: readDat)
        }

        buffer.deallocate()

        bodyStream.close()

        do {
            return try JSONSerialization.jsonObject(with: dat, options: JSONSerialization.ReadingOptions.allowFragments)
        } catch {

            print(error.localizedDescription)

            return nil
        }
    }
}
