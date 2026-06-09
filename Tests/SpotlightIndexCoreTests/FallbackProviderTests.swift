import Foundation
import XCTest
@testable import SpotlightIndexCore

final class FallbackProviderTests: XCTestCase {
    func testSafariHistoryProviderResolvesHistoryByTitleAndURL() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE history_items (id INTEGER PRIMARY KEY, url TEXT, title TEXT)")
            try db.execute("CREATE TABLE history_visits (id INTEGER PRIMARY KEY, history_item INTEGER, visit_time REAL)")
            try db.execute("INSERT INTO history_items VALUES (1, 'https://example.com/bennett', 'Bennett profile')")
            try db.execute("INSERT INTO history_visits VALUES (1, 1, 1000)")
        }

        let results = try SafariHistoryProvider(historyDBPath: dbPath).search(context("bennett"))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.source, "safari")
        XCTAssertEqual(results.first?.url, "https://example.com/bennett")
        XCTAssertEqual(results.first?.title, "Bennett profile")
    }

    func testSafariHistoryProviderResolvesHistoryWhenTitleIsOnVisitRows() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE history_items (id INTEGER PRIMARY KEY, url TEXT, domain_expansion TEXT)")
            try db.execute("CREATE TABLE history_visits (id INTEGER PRIMARY KEY, history_item INTEGER, visit_time REAL, title TEXT)")
            try db.execute("INSERT INTO history_items VALUES (1, 'https://www.amazon.co.uk/orders', 'amazon')")
            try db.execute("INSERT INTO history_visits VALUES (1, 1, 1000, 'Amazon orders')")
            try db.execute("INSERT INTO history_visits VALUES (2, 1, 2000, 'Amazon recent orders')")
        }

        let results = try SafariHistoryProvider(historyDBPath: dbPath).search(context("amazon"))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.source, "safari")
        XCTAssertEqual(results.first?.url, "https://www.amazon.co.uk/orders")
        XCTAssertEqual(results.first?.title, "Amazon recent orders")
        XCTAssertEqual(results.first?.metadata["visitCount"], .number(2))
        XCTAssertEqual(results.first?.metadata["visitedAt"], .string("2001-01-01T00:33:20Z"))
    }

    func testSafariHistoryProviderDedupesTrackingQueryVariants() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE history_items (id INTEGER PRIMARY KEY, url TEXT, title TEXT)")
            try db.execute("CREATE TABLE history_visits (id INTEGER PRIMARY KEY, history_item INTEGER, visit_time REAL)")
            try db.execute("INSERT INTO history_items VALUES (1, 'https://www.amazon.co.uk/s?k=wifi&utm_source=newsletter', 'Amazon older')")
            try db.execute("INSERT INTO history_items VALUES (2, 'https://www.amazon.co.uk/s?utm_source=ad&k=wifi', 'Amazon latest')")
            try db.execute("INSERT INTO history_items VALUES (3, 'https://www.amazon.co.uk/orders', 'Amazon orders')")
            try db.execute("INSERT INTO history_visits VALUES (1, 1, 1000)")
            try db.execute("INSERT INTO history_visits VALUES (2, 2, 3000)")
            try db.execute("INSERT INTO history_visits VALUES (3, 3, 2000)")
        }

        let results = try SafariHistoryProvider(historyDBPath: dbPath).search(context("amazon", limit: 3))

        XCTAssertEqual(results.map(\.title), ["Amazon latest", "Amazon orders"])
    }

    func testMailProviderResolvesEmailBySubjectSenderAndSnippet() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE messages (subject TEXT, sender TEXT, recipients TEXT, date_sent REAL, snippet TEXT, message_id TEXT, path TEXT, flags INTEGER, mailbox TEXT)")
            try db.execute("INSERT INTO messages VALUES ('Passport renewal', 'agent@example.com', 'bennett@example.com', 2000, 'Bring a photo', 'abc@example.com', '/mail/message.emlx', 17, 'Inbox')")
        }

        let results = try MailSQLiteProvider(envelopeDBPath: dbPath).search(context("passport"))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.source, "mail")
        XCTAssertEqual(results.first?.entityType, "email")
        XCTAssertEqual(results.first?.title, "Passport renewal")
        XCTAssertEqual(results.first?.metadata["recipients"], .string("bennett@example.com"))
        XCTAssertEqual(results.first?.metadata["snippet"], .string("Bring a photo"))
        XCTAssertEqual(results.first?.metadata["messageID"], .string("abc@example.com"))
        XCTAssertEqual(results.first?.metadata["mailbox"], .string("Inbox"))
        XCTAssertEqual(results.first?.metadata["flags"], .number(17))
        XCTAssertEqual(results.first?.path, "/mail/message.emlx")
        XCTAssertEqual(results.first?.id, "mail:1")
        XCTAssertEqual(results.first?.url, "message://%3Cabc@example.com%3E")
    }

    func testMailProviderItemReturnsBoundedBodyText() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let messageURL = folder.appendingPathComponent("message.emlx")
        try """
        128
        Subject: Your withdrawal request has been received.
        Content-Transfer-Encoding: quoted-printable

        Your money is on its way
        Amount: GBP 799.05
        """.write(to: messageURL, atomically: true, encoding: .utf8)
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE messages (subject TEXT, sender TEXT, recipients TEXT, date_sent REAL, snippet TEXT, message_id TEXT, path TEXT, flags INTEGER, mailbox TEXT)")
            try db.execute("INSERT INTO messages VALUES ('Your withdrawal request has been received.', 'no-reply@info.trading212.com', 'bennett@example.com', 1717902000, NULL, 'abc@example.com', '\(messageURL.path)', 0, 'Inbox')")
        }

        let item = try MailSQLiteProvider(envelopeDBPath: dbPath).item(id: "mail:1")

        XCTAssertEqual(item.id, "mail:1")
        XCTAssertEqual(item.source, "mail")
        XCTAssertEqual(item.title, "Your withdrawal request has been received.")
        XCTAssertEqual(item.metadata["bodyText"], .string("Your money is on its way Amount: GBP 799.05"))
        XCTAssertEqual(item.metadata["bodyExcerpt"], .string("Your money is on its way Amount: GBP 799.05"))
    }

    func testMailProviderMatchesCompactedSenderForSpacedQuery() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE messages (subject TEXT, sender TEXT, recipients TEXT, date_sent REAL, snippet TEXT)")
            try db.execute("INSERT INTO messages VALUES ('Your money is on its way', 'no-reply@info.trading212.com', 'bennett@example.com', 3000, NULL)")
            try db.execute("INSERT INTO messages VALUES ('You sent money elsewhere', 'other@example.com', 'bennett@example.com', 4000, NULL)")
        }

        let results = try MailSQLiteProvider(envelopeDBPath: dbPath).search(context("Trading 212"))

        XCTAssertEqual(results.map(\.title), ["Your money is on its way"])
    }

    func testMailProviderMatchesIntentTokensAcrossSenderAndSubject() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE messages (subject TEXT, sender TEXT, recipients TEXT, date_sent REAL, snippet TEXT)")
            try db.execute("INSERT INTO messages VALUES ('Your withdrawal request has been received', 'no-reply@info.trading212.com', 'bennett@example.com', 3000, NULL)")
            try db.execute("INSERT INTO messages VALUES ('You sent money to Trading 212 UK Limited', 'bank@example.com', 'bennett@example.com', 4000, NULL)")
        }

        let results = try MailSQLiteProvider(envelopeDBPath: dbPath).search(context("Trading 212 withdrawal"))

        XCTAssertEqual(results.map(\.title), ["Your withdrawal request has been received"])
    }

    func testMailProviderResolvesAppleEnvelopeShapeWithSubjectAndAddressTables() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE subjects (ROWID INTEGER PRIMARY KEY, subject TEXT)")
            try db.execute("CREATE TABLE addresses (ROWID INTEGER PRIMARY KEY, address TEXT, comment TEXT)")
            try db.execute("CREATE TABLE messages (subject INTEGER, sender INTEGER, date_sent REAL, snippet TEXT)")
            try db.execute("INSERT INTO subjects VALUES (1, 'Bennett itinerary')")
            try db.execute("INSERT INTO addresses VALUES (2, 'person@example.com', 'Person Example')")
            try db.execute("INSERT INTO messages VALUES (1, 2, 2000, 'Flights and hotels')")
        }

        let results = try MailSQLiteProvider(envelopeDBPath: dbPath).search(context("bennett"))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.source, "mail")
        XCTAssertEqual(results.first?.title, "Bennett itinerary")
        XCTAssertEqual(results.first?.subtitle, "person@example.com")
        XCTAssertEqual(results.first?.metadata["recipients"], .null)
        XCTAssertEqual(results.first?.metadata["snippet"], .string("Flights and hotels"))
    }

    func testMessagesProviderResolvesMessageTextHandleAndChat() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE message (ROWID INTEGER PRIMARY KEY, guid TEXT, text TEXT, handle_id INTEGER, date INTEGER, is_from_me INTEGER, service TEXT)")
            try db.execute("CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT, service TEXT)")
            try db.execute("CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, chat_identifier TEXT, display_name TEXT)")
            try db.execute("CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER)")
            try db.execute("INSERT INTO handle VALUES (2, 'person@example.com', 'iMessage')")
            try db.execute("INSERT INTO chat VALUES (3, 'chat-person@example.com', 'Bennett chat')")
            try db.execute("INSERT INTO message VALUES (1, 'message-guid', 'Passport photo is ready', 2, 2000000000000, 0, 'iMessage')")
            try db.execute("INSERT INTO chat_message_join VALUES (3, 1)")
        }

        let results = try MessagesSQLiteProvider(chatDBPath: dbPath).search(context("passport"))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.source, "messages")
        XCTAssertEqual(results.first?.entityType, "message")
        XCTAssertEqual(results.first?.title, "Passport photo is ready")
        XCTAssertEqual(results.first?.subtitle, "person@example.com")
        XCTAssertEqual(results.first?.url, "imessage://message-guid")
        XCTAssertEqual(results.first?.metadata["handle"], .string("person@example.com"))
        XCTAssertEqual(results.first?.metadata["chat"], .string("Bennett chat"))
        XCTAssertEqual(results.first?.metadata["service"], .string("iMessage"))
        XCTAssertEqual(results.first?.metadata["isFromMe"], .bool(false))
    }

    func testMessagesProviderSearchesAttributedBodyWhenTextIsNullOrEmpty() throws {
        let nullBody = try attributedBodyHex("Passport renewal is in the attributed body")
        let emptyBody = try attributedBodyHex("Boarding pass is also archived")
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE message (ROWID INTEGER PRIMARY KEY, guid TEXT, text TEXT, attributedBody BLOB, handle_id INTEGER, date INTEGER, is_from_me INTEGER, service TEXT)")
            try db.execute("CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT, service TEXT)")
            try db.execute("INSERT INTO handle VALUES (2, 'person@example.com', 'iMessage')")
            try db.execute("INSERT INTO message VALUES (1, 'message-null', NULL, X'\(nullBody)', 2, 2000000000000, 0, 'iMessage')")
            try db.execute("INSERT INTO message VALUES (2, 'message-empty', '', X'\(emptyBody)', 2, 3000000000000, 0, 'iMessage')")
        }

        let passportResults = try MessagesSQLiteProvider(chatDBPath: dbPath).search(context("passport"))
        let boardingResults = try MessagesSQLiteProvider(chatDBPath: dbPath).search(context("boarding"))

        XCTAssertEqual(passportResults.first?.title, "Passport renewal is in the attributed body")
        XCTAssertEqual(passportResults.first?.url, "imessage://message-null")
        XCTAssertEqual(boardingResults.first?.title, "Boarding pass is also archived")
        XCTAssertEqual(boardingResults.first?.url, "imessage://message-empty")
    }

    func testCalendarProviderResolvesEventsByTitleNotesAndLocation() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE events (id INTEGER PRIMARY KEY, title TEXT, notes TEXT, location TEXT, start_date REAL, end_date REAL, calendar_title TEXT)")
            try db.execute("INSERT INTO events VALUES (1, 'Bennett coffee', 'Discuss search', 'London', 3000, 3600, 'Work')")
        }

        let results = try LocalCalendarProvider(calendarDBPath: dbPath).search(context("bennett"))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.source, "calendar")
        XCTAssertEqual(results.first?.entityType, "calendar-event")
        XCTAssertEqual(results.first?.title, "Bennett coffee")
    }

    func testRemindersProviderResolvesRemindersByTitleAndNotes() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE reminders (id INTEGER PRIMARY KEY, title TEXT, notes TEXT, due_date REAL, completed INTEGER)")
            try db.execute("INSERT INTO reminders VALUES (1, 'Find passport', 'Check Photos fallback', 4000, 0)")
        }

        let results = try LocalRemindersProvider(remindersDBPath: dbPath).search(context("passport"))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.source, "reminders")
        XCTAssertEqual(results.first?.entityType, "reminder")
        XCTAssertEqual(results.first?.title, "Find passport")
    }

    func testNotesProviderResolvesNotesByTitleAndBody() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT, body TEXT, modified_at REAL)")
            try db.execute("INSERT INTO notes VALUES (1, 'Bennett note', 'This note includes my name', 5000)")
        }

        let results = try NotesSQLiteProvider(notesDBPath: dbPath).search(context("bennett"))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.source, "notes")
        XCTAssertEqual(results.first?.entityType, "note")
        XCTAssertEqual(results.first?.title, "Bennett note")
        XCTAssertEqual(results.first?.metadata["matchReason"], .string("title"))
    }

    func testNotesProviderRanksTitleMatchesAheadOfNewerBodyMatches() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT, body TEXT, modified_at REAL)")
            try db.execute("INSERT INTO notes VALUES (1, 'Older Bennett title', 'Body', 1000)")
            try db.execute("INSERT INTO notes VALUES (2, 'Newer body only', 'Mentions Bennett here', 9000)")
        }

        let results = try NotesSQLiteProvider(notesDBPath: dbPath).search(context("bennett"))

        XCTAssertEqual(results.map(\.title), ["Older Bennett title", "Newer body only"])
        XCTAssertEqual(results.map { $0.metadata["matchReason"] }, [.string("title"), .string("body")])
    }

    func testNotesProviderResolvesAppleNotesShapeWhenAvailable() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE ZICCLOUDSYNCINGOBJECT (Z_PK INTEGER PRIMARY KEY, ZTITLE1 TEXT, ZSNIPPET TEXT, ZMODIFICATIONDATE1 REAL)")
            try db.execute("INSERT INTO ZICCLOUDSYNCINGOBJECT VALUES (1, 'Project note', 'Bennett appears here', 6000)")
        }

        let results = try NotesSQLiteProvider(notesDBPath: dbPath).search(context("bennett"))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.source, "notes")
        XCTAssertEqual(results.first?.title, "Project note")
    }

    func testNotesProviderResolvesLinkedAppleNoteDataText() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE ZICCLOUDSYNCINGOBJECT (Z_PK INTEGER PRIMARY KEY, ZTITLE1 TEXT, ZMODIFICATIONDATE1 REAL)")
            try db.execute("CREATE TABLE ZICNOTEDATA (Z_PK INTEGER PRIMARY KEY, ZNOTE INTEGER, ZPLAINTEXT TEXT)")
            try db.execute("INSERT INTO ZICCLOUDSYNCINGOBJECT VALUES (1, 'Private note', 6000)")
            try db.execute("INSERT INTO ZICNOTEDATA VALUES (10, 1, 'This note body mentions Bennett')")
        }

        let results = try NotesSQLiteProvider(notesDBPath: dbPath).search(context("bennett"))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.source, "notes")
        XCTAssertEqual(results.first?.title, "Private note")
        XCTAssertEqual(results.first?.subtitle, "This note body mentions Bennett")
    }

    func testNotesProviderDecodesGzipProtobufNoteData() throws {
        let gzipProtobuf = "1f8b0800d128286a02ffe352135271ce4f49ad5048afca2c5048ca4fa954c8c9cc4b55c8cf4be52a4e4dcecf4b01f301a6a987bf28000000"
        let expectedBody = "Codex gzip body line one\nsecond line"
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE ZICCLOUDSYNCINGOBJECT (Z_PK INTEGER PRIMARY KEY, ZTITLE1 TEXT, ZSNIPPET TEXT, ZIDENTIFIER TEXT, ZMODIFICATIONDATE1 REAL)")
            try db.execute("CREATE TABLE ZICNOTEDATA (Z_PK INTEGER PRIMARY KEY, ZNOTE INTEGER, ZDATA BLOB)")
            try db.execute("INSERT INTO ZICCLOUDSYNCINGOBJECT VALUES (1, 'Compressed note', 'Short preview only', 'GZIP-NOTE-1', 6000)")
            try db.execute("INSERT INTO ZICNOTEDATA VALUES (10, 1, X'\(gzipProtobuf)')")
        }
        let provider = NotesSQLiteProvider(notesDBPath: dbPath)

        let result = try XCTUnwrap(provider.search(context("codex")).first)
        let item = try provider.item(id: result.id)

        XCTAssertEqual(result.title, "Compressed note")
        XCTAssertEqual(result.subtitle, "Codex gzip body line one second line")
        XCTAssertEqual(result.metadata["matchReason"], .string("body"))
        XCTAssertEqual(item.metadata["body"], .string(expectedBody))
        XCTAssertEqual(item.url, "notes://showNote?identifier=GZIP-NOTE-1")
    }

    func testNotesProviderDoesNotUseCompressedNoiseAsSnippet() throws {
        let invalidGzip = "1f8b08000000000000ff000000000000000000"
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE ZICCLOUDSYNCINGOBJECT (Z_PK INTEGER PRIMARY KEY, ZTITLE1 TEXT, ZMODIFICATIONDATE1 REAL)")
            try db.execute("CREATE TABLE ZICNOTEDATA (Z_PK INTEGER PRIMARY KEY, ZNOTE INTEGER, ZDATA BLOB)")
            try db.execute("INSERT INTO ZICCLOUDSYNCINGOBJECT VALUES (1, 'Codex title only', 6000)")
            try db.execute("INSERT INTO ZICNOTEDATA VALUES (10, 1, X'\(invalidGzip)')")
        }

        let result = try XCTUnwrap(NotesSQLiteProvider(notesDBPath: dbPath).search(context("codex")).first)

        XCTAssertEqual(result.title, "Codex title only")
        XCTAssertNil(result.subtitle)
        XCTAssertEqual(result.metadata["matchReason"], .string("title"))
    }

    func testNotesProviderLoadsFullFixtureNoteByRawID() throws {
        let body = "Line one mentions Bennett.\nLine two has the full private note body."
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT, body TEXT, modified_at REAL, identifier TEXT)")
            try db.execute("INSERT INTO notes VALUES (1, 'Bennett note', '\(body)', 5000, 'NOTE-IDENTIFIER-1')")
        }

        let item = try NotesSQLiteProvider(notesDBPath: dbPath).item(id: "1")

        XCTAssertEqual(item.source, "notes")
        XCTAssertEqual(item.entityType, "note")
        XCTAssertEqual(item.title, "Bennett note")
        XCTAssertEqual(item.url, "notes://showNote?identifier=NOTE-IDENTIFIER-1")
        XCTAssertEqual(item.metadata["body"], .string(body))
        XCTAssertEqual(item.metadata["bodyLength"], .number(Double(body.count)))
    }

    func testNotesProviderLoadsFullAppleNoteByStableSearchID() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE ZICCLOUDSYNCINGOBJECT (Z_PK INTEGER PRIMARY KEY, ZTITLE1 TEXT, ZSNIPPET TEXT, ZIDENTIFIER TEXT, ZMODIFICATIONDATE1 REAL)")
            try db.execute("CREATE TABLE ZICNOTEDATA (Z_PK INTEGER PRIMARY KEY, ZNOTE INTEGER, ZPLAINTEXT TEXT)")
            try db.execute("INSERT INTO ZICCLOUDSYNCINGOBJECT VALUES (7, 'Project note', 'short Bennett snippet', 'APPLE-NOTE-7', 6000)")
            try db.execute("INSERT INTO ZICNOTEDATA VALUES (10, 7, 'Full Bennett body loaded from linked note data')")
        }
        let provider = NotesSQLiteProvider(notesDBPath: dbPath)
        let result = try XCTUnwrap(provider.search(context("bennett")).first)

        let item = try provider.item(id: result.id)

        XCTAssertEqual(item.id, result.id)
        XCTAssertEqual(item.url, "notes://showNote?identifier=APPLE-NOTE-7")
        XCTAssertEqual(item.metadata["notesIdentifier"], .string("APPLE-NOTE-7"))
        XCTAssertEqual(item.metadata["openURL"], .string("notes://showNote?identifier=APPLE-NOTE-7"))
        XCTAssertEqual(item.metadata["body"], .string("Full Bennett body loaded from linked note data"))
    }

    func testPhotosProviderResolvesNamedPersonAssets() throws {
        let libraryURL = try makePhotosFixture(assetUUID: "ABCDEF12-3456-7890-ABCD-EF1234567890")

        let results = try PhotosSQLiteProvider(libraryURL: libraryURL).search(context("bennett"))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.source, "photos")
        XCTAssertEqual(results.first?.entityType, "photo")
        XCTAssertEqual(results.first?.subtitle, "Bennett")
        XCTAssertEqual(results.first?.metadata["matchReason"], .string("person"))
        XCTAssertEqual(results.first?.metadata["mediaKind"], .string("image"))
        XCTAssertNotNil(results.first?.path)
    }

    func testPhotosThumbnailResolverReturnsSafeDerivative() throws {
        let uuid = "ABCDEF12-3456-7890-ABCD-EF1234567890"
        let libraryURL = try makePhotosFixture(assetUUID: uuid)

        let file = try PhotosAssetResolver(libraryURL: libraryURL).thumbnail(uuid: uuid)

        XCTAssertEqual(file.contentType, "image/jpeg")
        XCTAssertTrue(file.path.hasPrefix(libraryURL.path))
        XCTAssertEqual(try String(contentsOfFile: file.path, encoding: .utf8), "fixture")
    }

    func testPhotosProviderResolvesSearchLexemeAssets() throws {
        let libraryURL = try makePhotosFixture(assetUUID: "ABCDEF12-3456-7890-ABCD-EF1234567890")

        let results = try PhotosSQLiteProvider(libraryURL: libraryURL).search(context("passport"))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.source, "photos")
        XCTAssertEqual(results.first?.metadata["matchReason"], .string("photos-search"))
    }

    func testPhotosProviderResolvesOriginalPathUsingAssetDirectory() throws {
        let libraryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("photoslibrary")
        let databaseURL = libraryURL.appendingPathComponent("database")
        let originalURL = libraryURL.appendingPathComponent("originals/C/IMG_0001.jpeg")
        try FileManager.default.createDirectory(at: databaseURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original".utf8).write(to: originalURL)
        defer { try? FileManager.default.removeItem(at: libraryURL) }

        let photosDB = try SQLiteDatabase(path: databaseURL.appendingPathComponent("Photos.sqlite").path, readOnly: false)
        try photosDB.execute("CREATE TABLE ZPERSON (Z_PK INTEGER PRIMARY KEY, ZDISPLAYNAME TEXT, ZFULLNAME TEXT, ZPERSONUUID TEXT)")
        try photosDB.execute("CREATE TABLE ZASSET (Z_PK INTEGER PRIMARY KEY, ZUUID TEXT, ZFILENAME TEXT, ZDIRECTORY TEXT, ZUNIFORMTYPEIDENTIFIER TEXT, ZWIDTH INTEGER, ZHEIGHT INTEGER, ZDATECREATED REAL, ZHIDDEN INTEGER, ZTRASHEDSTATE INTEGER, ZVISIBILITYSTATE INTEGER)")
        try photosDB.execute("CREATE TABLE ZDETECTEDFACE (Z_PK INTEGER PRIMARY KEY, ZPERSONFORFACE INTEGER, ZASSETFORFACE INTEGER, ZHIDDEN INTEGER, ZISINTRASH INTEGER)")
        try photosDB.execute("INSERT INTO ZPERSON VALUES (1, 'Bennett', 'Bennett Blackham', 'PERSON-1')")
        try photosDB.execute("INSERT INTO ZASSET VALUES (1, 'ABCDEF12-3456-7890-ABCD-EF1234567890', 'IMG_0001.jpeg', 'C', 'public.jpeg', 360, 480, 5000, 0, 0, 0)")
        try photosDB.execute("INSERT INTO ZDETECTEDFACE VALUES (1, 1, 1, 0, 0)")

        let result = try XCTUnwrap(PhotosSQLiteProvider(libraryURL: libraryURL).search(context("bennett")).first)

        XCTAssertEqual(result.path, originalURL.path)
    }

    func testServiceFansOutAndReportsProviderStatuses() throws {
        let service = SpotlightSearchService(providers: [
            StubProvider(source: .contacts, title: "Bennett Blackham"),
            FailingProvider(source: .mail)
        ])

        let response = try service.search(SearchRequest(query: "bennett", sources: ["contacts", "mail"], limit: 10))

        XCTAssertEqual(response.results.map(\.source), ["contacts"])
        XCTAssertEqual(response.providers.first(where: { $0.source == "contacts" })?.status, "ok")
        XCTAssertEqual(response.providers.first(where: { $0.source == "mail" })?.status, "unavailable")
    }

    func testServiceDefaultsToAllRegisteredProviders() throws {
        let service = SpotlightSearchService(providers: [
            StubProvider(source: .contacts, title: "Bennett Blackham"),
            StubProvider(source: .photos, title: "Bennett photo"),
            StubProvider(source: .notes, title: "Bennett note")
        ])

        let response = try service.search(SearchRequest(query: "bennett", limit: 10))

        XCTAssertEqual(Set(response.results.map(\.source)), ["contacts", "photos", "notes"])
    }

    func testServiceLoadsProviderItemBySourceAndID() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT, body TEXT, modified_at REAL)")
            try db.execute("INSERT INTO notes VALUES (1, 'Loaded note', 'Full note body', 5000)")
        }
        let service = SpotlightSearchService(providers: [
            NotesSQLiteProvider(notesDBPath: dbPath)
        ])

        let response = try service.item(source: "notes", id: "1")

        XCTAssertEqual(response.item.source, "notes")
        XCTAssertEqual(response.item.title, "Loaded note")
        XCTAssertEqual(response.item.metadata["body"], .string("Full note body"))
    }

    func testServiceOpensProviderItemURL() throws {
        let dbPath = try makeTempDB { db in
            try db.execute("CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT, body TEXT, modified_at REAL, identifier TEXT)")
            try db.execute("INSERT INTO notes VALUES (1, 'Open note', 'Full note body', 5000, 'NOTE-OPEN-1')")
        }
        let opener = RecordingItemOpener()
        let service = SpotlightSearchService(
            providers: [NotesSQLiteProvider(notesDBPath: dbPath)],
            itemOpener: opener
        )

        let response = try service.open(OpenItemRequest(source: "notes", id: "1"))

        XCTAssertTrue(response.opened)
        XCTAssertEqual(response.target, "notes://showNote?identifier=NOTE-OPEN-1")
        XCTAssertEqual(response.item?.title, "Open note")
        XCTAssertEqual(opener.openedURLs.map(\.absoluteString), ["notes://showNote?identifier=NOTE-OPEN-1"])
    }

    func testProviderReadinessListsAllSources() {
        let response = SpotlightSearchService().providerReadiness()

        XCTAssertEqual(Set(response.providers.map(\.source)), Set(SearchSource.allCases.map(\.rawValue)))
        XCTAssertTrue(response.providers.allSatisfy { !$0.status.isEmpty && !$0.summary.isEmpty })
    }

    func testPermissionBootstrapperTreatsPhotosAsManualProtectedSource() throws {
        let response = try SpotlightSearchService().requestPermissions(PermissionRequest(sources: ["photos", "files"]))

        XCTAssertEqual(response.results.first(where: { $0.source == "photos" })?.status, "manual")
        XCTAssertNotNil(response.results.first(where: { $0.source == "photos" })?.setupHint)
        XCTAssertEqual(response.results.first(where: { $0.source == "files" })?.status, "not_required")
    }

    func testFileSearchResultAnnotatesFilenameMatches() {
        let record = SpotlightRecord(
            id: "file-1",
            path: "/Users/bennett/Documents/passport.pdf",
            displayName: "passport.pdf",
            contentType: "com.adobe.pdf",
            kind: "PDF",
            bundleIdentifier: nil,
            createdAt: nil,
            modifiedAt: nil,
            authors: nil,
            sizeBytes: nil,
            metadata: [:]
        )

        XCTAssertEqual(record.searchResult(query: "passport").metadata["matchReason"], .string("filename"))
        XCTAssertEqual(record.searchResult(query: "renewal").metadata["matchReason"], .string("metadata"))
    }

    func testFileProviderDefaultNoiseFilterSkipsBuildArtifactsOnlyWithoutScopes() {
        let record = SpotlightRecord(
            id: "file-2",
            path: "/Users/bennett/project/node_modules/pkg/index.js",
            displayName: "index.js",
            contentType: "public.javascript",
            kind: "JavaScript",
            bundleIdentifier: nil,
            createdAt: nil,
            modifiedAt: nil,
            authors: nil,
            sizeBytes: nil,
            metadata: [:]
        )

        XCTAssertTrue(record.isNoisyDefaultResult(whenScopesAre: []))
        XCTAssertFalse(record.isNoisyDefaultResult(whenScopesAre: ["/Users/bennett/project/node_modules"]))
    }

    func testFileProviderScopedFallbackFindsFreshFilenameAndContentMatches() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }

        let filenameURL = folder.appendingPathComponent("fresh-passport-filename.txt")
        let contentURL = folder.appendingPathComponent("content-only.txt")
        try "filename fixture".write(to: filenameURL, atomically: true, encoding: .utf8)
        try "body mentions fresh-passport-content".write(to: contentURL, atomically: true, encoding: .utf8)

        let filenameResults = try SpotlightFileProvider().search(ProviderSearchContext(query: "fresh-passport-filename", types: [], onlyIn: [folder.path], limit: 10))
        let contentResults = try SpotlightFileProvider().search(ProviderSearchContext(query: "fresh-passport-content", types: [], onlyIn: [folder.path], limit: 10))

        XCTAssertTrue(filenameResults.contains { $0.path == filenameURL.path && $0.metadata["matchReason"] == .string("filename") })
        XCTAssertTrue(contentResults.contains { $0.path == contentURL.path && $0.metadata["matchReason"] == .string("content") })
    }

    func testSchemaIncludesProviderSpecificFields() {
        let schema = SpotlightSearchService().schema()

        XCTAssertEqual(Set(schema.providerFields.keys), Set(SearchSource.allCases.map(\.rawValue)))
        XCTAssertEqual(schema.providerFields["photos"]?.metadataFields["matchReason"], "person or photos-search.")
        XCTAssertEqual(schema.providerFields["safari"]?.metadataFields["visitCount"], "Number of recorded visits for the URL.")
    }

    func testCapabilitiesIncludeLiveReadinessAndLimitations() {
        let capabilities = SpotlightSearchService().capabilities()

        XCTAssertEqual(Set(capabilities.sources.map(\.source)), Set(SearchSource.allCases.map(\.rawValue)))
        XCTAssertFalse(capabilities.sources.first(where: { $0.source == "mail" })?.permissionRequired.isEmpty ?? true)
        XCTAssertFalse(capabilities.sources.first(where: { $0.source == "notes" })?.limitations.isEmpty ?? true)
    }

    func testDeepSearchCombinesQueriesAndRegexes() throws {
        let service = SpotlightSearchService(providers: [
            StubProvider(source: .files, title: "Passport renewal document")
        ])

        let response = try service.deepSearch(DeepSearchRequest(
            queries: ["passport", "document"],
            regexes: ["renewal"],
            sources: ["files"],
            limitPerQuery: 10,
            limit: 10
        ))

        XCTAssertEqual(response.count, 1)
        XCTAssertEqual(response.results.first?.matchedQueries, ["document", "passport"])
        XCTAssertEqual(response.results.first?.matchedRegexes, ["renewal"])
    }

    func testExtractFindsPassportNumberFromMRZTextAndSavesPrivateOutput() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let output = folder.appendingPathComponent("passport-number.txt")
        let text = """
        P<GBRBLACKHAM<<BENNETT<<<<<<<<<<<<<<<<<<<<
        1234567890GBR9001019M3001012<<<<<<<<<<<<<<04
        """

        let response = try SpotlightSearchService().extract(ExtractRequest(
            entityTypes: ["passport_number"],
            text: text,
            saveTo: output.path
        ))

        XCTAssertEqual(response.count, 1)
        XCTAssertEqual(response.entities.first?.value, "123456789")
        XCTAssertEqual(response.entities.first?.confidence, 100)
        XCTAssertEqual(response.entities.first?.reason, "mrz")
        XCTAssertEqual(response.savedTo, output.path)
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: output.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
        XCTAssertTrue(try String(contentsOf: output).contains("passport_number: 123456789"))
    }

    private func context(_ query: String, limit: Int = 10) -> ProviderSearchContext {
        ProviderSearchContext(query: query, types: [], onlyIn: [], limit: limit)
    }

    private func makeTempDB(_ build: (SQLiteDatabase) throws -> Void) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let db = try SQLiteDatabase(path: url.path, readOnly: false)
        try build(db)
        return url.path
    }

    private func attributedBodyHex(_ string: String) throws -> String {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: NSAttributedString(string: string),
            requiringSecureCoding: false
        )
        return data.map { String(format: "%02x", $0) }.joined()
    }

    private func makePhotosFixture(assetUUID: String) throws -> URL {
        let libraryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("photoslibrary")
        let databaseURL = libraryURL.appendingPathComponent("database")
        let searchURL = databaseURL.appendingPathComponent("search")
        let derivativesURL = libraryURL.appendingPathComponent("resources/derivatives/masters/A")
        try FileManager.default.createDirectory(at: searchURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: derivativesURL, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: derivativesURL.appendingPathComponent("\(assetUUID)_4_5005_c.jpeg"))

        let photosDB = try SQLiteDatabase(path: databaseURL.appendingPathComponent("Photos.sqlite").path, readOnly: false)
        try photosDB.execute("CREATE TABLE ZPERSON (Z_PK INTEGER PRIMARY KEY, ZDISPLAYNAME TEXT, ZFULLNAME TEXT, ZPERSONUUID TEXT)")
        try photosDB.execute("CREATE TABLE ZASSET (Z_PK INTEGER PRIMARY KEY, ZUUID TEXT, ZFILENAME TEXT, ZUNIFORMTYPEIDENTIFIER TEXT, ZWIDTH INTEGER, ZHEIGHT INTEGER, ZDATECREATED REAL, ZHIDDEN INTEGER, ZTRASHEDSTATE INTEGER, ZVISIBILITYSTATE INTEGER)")
        try photosDB.execute("CREATE TABLE ZDETECTEDFACE (Z_PK INTEGER PRIMARY KEY, ZPERSONFORFACE INTEGER, ZASSETFORFACE INTEGER, ZHIDDEN INTEGER, ZISINTRASH INTEGER)")
        try photosDB.execute("INSERT INTO ZPERSON VALUES (1, 'Bennett', 'Bennett Blackham', 'PERSON-1')")
        try photosDB.execute("INSERT INTO ZASSET VALUES (1, '\(assetUUID)', '\(assetUUID).jpeg', 'public.jpeg', 360, 480, 5000, 0, 0, 0)")
        try photosDB.execute("INSERT INTO ZDETECTEDFACE VALUES (1, 1, 1, 0, 0)")

        let searchDB = try SQLiteDatabase(path: searchURL.appendingPathComponent("leo.sqlite").path, readOnly: false)
        try searchDB.execute("CREATE TABLE lexicon (pk INTEGER PRIMARY KEY, lexeme_id INTEGER, type INTEGER, category INTEGER, content TEXT, identifier TEXT, score REAL)")
        try searchDB.execute("CREATE TABLE items (pk INTEGER PRIMARY KEY, identifier TEXT, type INTEGER, lexeme_ids BLOB)")
        try searchDB.execute("INSERT INTO lexicon VALUES (1, 42, 1, 4000, 'Passport', 'scene/960', 1.0)")
        try searchDB.execute("INSERT INTO items VALUES (1, '\(assetUUID)', 1, X'2A000000')")

        return libraryURL
    }
}

private struct StubProvider: SearchProvider {
    let source: SearchSource
    let title: String

    func search(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        [SearchResultRecord(
            id: SearchUtilities.stableID([source.rawValue, title]),
            source: source.rawValue,
            entityType: source.rawValue,
            title: title
        )]
    }
}

private struct FailingProvider: SearchProvider {
    let source: SearchSource

    func search(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        throw ProviderError.unavailable("fixture failure")
    }
}

private final class RecordingItemOpener: ItemOpening, @unchecked Sendable {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) throws {
        openedURLs.append(url)
    }
}
