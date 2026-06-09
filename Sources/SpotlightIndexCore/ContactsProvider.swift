import Contacts
import Foundation

struct ContactsProvider: SearchProvider {
    let source: SearchSource = .contacts

    func search(_ context: ProviderSearchContext) throws -> [SearchResultRecord] {
        guard context.types.isEmpty else {
            return []
        }
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else {
            throw ProviderError.unavailable("Contacts permission is \(status)")
        }

        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        let needle = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        var records: [SearchResultRecord] = []

        try store.enumerateContacts(with: request) { contact, stop in
            let emails = contact.emailAddresses.map { String($0.value) }
            let phones = contact.phoneNumbers.map { $0.value.stringValue }
            let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let haystack = ([name, contact.organizationName] + emails + phones).joined(separator: " ")
            if needle.isEmpty || SearchUtilities.contains(haystack, needle) {
                records.append(SearchResultRecord(
                    id: SearchUtilities.stableID([SearchSource.contacts.rawValue, contact.identifier]),
                    source: SearchSource.contacts.rawValue,
                    entityType: "contact",
                    title: name.isEmpty ? contact.organizationName : name,
                    subtitle: emails.first ?? phones.first,
                    metadata: [
                        "identifier": .string(contact.identifier),
                        "emails": .array(emails.map(JSONValue.string)),
                        "phones": .array(phones.map(JSONValue.string)),
                        "organization": contact.organizationName.isEmpty ? .null : .string(contact.organizationName),
                        "birthday": birthdayValue(contact.birthday)
                    ]
                ))
            }
            if records.count >= context.limit {
                stop.pointee = true
            }
        }

        return records
    }

    private func birthdayValue(_ birthday: DateComponents?) -> JSONValue {
        guard let birthday else {
            return .null
        }

        var object: [String: JSONValue] = [:]
        if let year = birthday.year {
            object["year"] = .number(Double(year))
        }
        if let month = birthday.month {
            object["month"] = .number(Double(month))
        }
        if let day = birthday.day {
            object["day"] = .number(Double(day))
        }
        return .object(object)
    }
}
