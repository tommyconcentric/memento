import SwiftUI

/// Phone entry that groups the digits as they're typed, the way iOS Contacts
/// does, and shows the country's flag once the number names one with a `+` or
/// `00` prefix.
struct PhoneNumberField: View {
    @Binding var text: String
    var title = "Phone"

    /// What this field last wrote back. Rewriting the text fires `onChange`
    /// again, and regrouping can shorten it. "(415) 5551" becomes "415-5551",
    /// which is indistinguishable from a backspace. Recognising our own echo
    /// is what stops that from swallowing the digit just typed.
    @State private var lastWritten: String?

    private var region: PhoneRegion? {
        PhoneNumberFormatter.region(for: text)
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField(title, text: $text)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .onChange(of: text) { previous, current in
                    guard current != lastWritten else { return }
                    let formatted = PhoneNumberFormatter.formatWhileTyping(old: previous, new: current)
                    guard formatted != current else { return }
                    lastWritten = formatted
                    text = formatted
                }
            if let region {
                CountryFlagView(region: region)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: region?.iso)
    }
}

/// The country's flag, sized to sit beside a line of body text.
struct CountryFlagView: View {
    let region: PhoneRegion

    var body: some View {
        Text(region.flag)
            .font(.title3)
            .accessibilityLabel(Text(region.localizedName))
    }
}
