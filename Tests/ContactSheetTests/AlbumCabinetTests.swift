import XCTest
@testable import ContactSheet

final class AlbumCabinetTests: XCTestCase {
    func testEveryAlbumFitsOnceAcrossWindowSizes() {
        for width in [CGFloat(280), 700, 960] {
            let columns = AlbumCabinet.columns(width: width)
            XCTAssertLessThanOrEqual(CGFloat(columns) * 33.6 + CGFloat(columns - 1) * 8 + 64, width)
            XCTAssertLessThanOrEqual(columns, 18)
            for count in [0, 5, 30, 100] {
                let ids = Array(0..<count)
                let rows = (0..<AlbumCabinet.rowCount(count, columns: columns)).map {
                    Array(ids.dropFirst($0 * columns).prefix(columns))
                }
                XCTAssertEqual(rows.flatMap { $0 }, ids)
                XCTAssertTrue(rows.allSatisfy { !$0.isEmpty && $0.count <= columns })
            }
        }
    }

}
