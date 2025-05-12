//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public extension Sequence where Element: SignedInteger {
    func sum() -> Element {
        reduce(0, +)
    }
}

public extension Sequence where Element: UnsignedInteger {
    func sum() -> Element {
        reduce(0, +)
    }
}

