import Testing
import Foundation
@testable import Papyro

struct IdentifierParserTests {
    let parser = IdentifierParser()

    @Test func parsesDOIFromText() {
        let text = "This paper (doi: 10.1038/s41586-024-07998-6) describes..."
        let result = parser.parse(text)
        #expect(result.doi == "10.1038/s41586-024-07998-6")
        #expect(result.bestIdentifier == "10.1038/s41586-024-07998-6")
    }

    @Test func parsesDOIWithHTTPSPrefix() {
        let text = "Available at https://doi.org/10.1126/science.abcdefg"
        let result = parser.parse(text)
        #expect(result.doi == "10.1126/science.abcdefg")
    }

    @Test func parsesDOIWithoutPrefix() {
        let text = "DOI 10.48550/arXiv.1706.03762"
        let result = parser.parse(text)
        #expect(result.doi == "10.48550/arXiv.1706.03762")
    }

    @Test func parsesArXivId() {
        let text = "arXiv:2401.12345v2 [cs.CL]"
        let result = parser.parse(text)
        #expect(result.arxivId == "2401.12345v2")
    }

    @Test func parsesArXivIdWithoutVersion() {
        let text = "See arxiv preprint 2312.00001"
        let result = parser.parse(text)
        #expect(result.arxivId == "2312.00001")
    }

    @Test func parsesPMID() {
        let text = "PMID: 12345678"
        let result = parser.parse(text)
        #expect(result.pmid == "12345678")
    }

    @Test func parsesPMIDWithoutColon() {
        let text = "PMID12345678"
        let result = parser.parse(text)
        #expect(result.pmid == "12345678")
    }

    @Test func parsesISBN13() {
        let text = "ISBN 978-0-13-468599-1"
        let result = parser.parse(text)
        #expect(result.isbn == "978-0-13-468599-1")
    }

    @Test func prioritizesDOIOverArXiv() {
        let text = "doi: 10.48550/arXiv.1706.03762 arXiv:1706.03762v1"
        let result = parser.parse(text)
        #expect(result.doi != nil)
        #expect(result.arxivId != nil)
        #expect(result.bestIdentifier == result.doi)
    }

    @Test func returnsEmptyForNoIdentifiers() {
        let text = "This is a paper about machine learning with no identifiers."
        let result = parser.parse(text)
        #expect(result.isEmpty)
        #expect(result.bestIdentifier == nil)
    }
}
