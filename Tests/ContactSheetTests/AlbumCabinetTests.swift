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

    @MainActor func testYearGroupingSearchAndSort() {
        let albums = [("Summer 10", 2026), ("Summer 2", 2026), ("Winter", 2025)].map { name, year in
            let album = ContactAlbum(name: name)
            album.createdAt = Calendar.current.date(from: DateComponents(year: year, month: 6, day: 1))!
            return album
        }
        XCTAssertEqual(AlbumCabinet.sections(albums, query: "", sort: "newest").map(\.year), [2026, 2025])
        XCTAssertEqual(AlbumCabinet.sections(albums, query: "", sort: "oldest").map(\.year), [2025, 2026])
        let results = AlbumCabinet.sections(albums, query: "  SUMMER ", sort: "name")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.albums.map(\.name), ["Summer 2", "Summer 10"])
        XCTAssertTrue(AlbumCabinet.sections(albums, query: "missing", sort: "newest").isEmpty)
    }
}
