import XCTest
import UIKit
import ChessMeCore
@testable import ChessMe

final class BoardDesignTests: XCTestCase {
    func testEveryPieceDesignIsIncludedAsAnOriginalColorSquareAsset() throws {
        for design in ChessBoardDesign.allCases {
            for side in Side.allCases {
                for kind in PieceKind.allCases {
                    let name = design.assetName(for: Piece(kind: kind, side: side))
                    let image = try XCTUnwrap(UIImage(named: name), "Missing bundled piece: \(name)")
                    XCTAssertGreaterThan(image.size.width, 0, name)
                    XCTAssertEqual(image.size.width, image.size.height, "The full square canvas must be preserved: \(name)")
                    XCTAssertEqual(image.renderingMode, .alwaysOriginal, "Piece colors must not be tinted: \(name)")
                }
            }
        }
    }
}
