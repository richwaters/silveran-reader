import Testing

@testable import SilveranKitCommon
@testable import SilveranKitMacApp

@Test func publicationYearExtractsFourDigitYearFromSupportedDates() async throws {
    #expect(BookMetadata.publicationYear(from: "1950-01-02T00:00:00.000Z") == "1950")
    #expect(BookMetadata.publicationYear(from: "1987-09-16") == "1987")
    #expect(BookMetadata.publicationYear(from: " 1989-01-01T05:00:00.000Z ") == "1989")
    #expect(BookMetadata.publicationYear(from: "Unknown") == nil)
    #expect(BookMetadata.publicationYear(from: nil) == nil)
}

@Test func publicationYearSmartShelfNormalizesLegacyTimestampValues() async throws {
    let book = BookMetadata(
        uuid: "book-id",
        title: "Book",
        subtitle: nil,
        description: nil,
        language: nil,
        createdAt: nil,
        updatedAt: nil,
        publicationDate: "1950-01-02T00:00:00.000Z",
        authors: nil,
        narrators: nil,
        creators: nil,
        series: nil,
        tags: nil,
        collections: nil,
        ebook: nil,
        audiobook: nil,
        readaloud: nil,
        status: nil,
        position: nil,
        rating: nil,
    )

    let condition = ShelfCondition.publicationYear(
        mode: .include,
        values: ["1950-01-02T00:00:00.000Z"],
    )

    #expect(book.sortablePublicationYear == "1950")
    #expect(condition.matches(book, progress: 0))
}
