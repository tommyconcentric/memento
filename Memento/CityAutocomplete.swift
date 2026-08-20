import SwiftUI
import Combine
import MapKit

// MARK: - City search

/// Autocompletes city names through MapKit as the user types. Every city in
/// Apple Maps is reachable, and results arrive ranked by relevance (the big
/// city rises above its namesakes; typing narrows to the small one).
///
/// This is the app's one non-CloudKit network call: the typed query goes to
/// Apple's Maps servers, nothing more. PRIVACY.md documents it.
@MainActor
final class CityAutocomplete: NSObject, ObservableObject {
    @Published var completions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        if #available(iOS 18.0, *) {
            // Cities only: no street addresses in the dropdown.
            completer.addressFilter = MKAddressFilter(including: [.locality, .subLocality])
        }
    }

    func search(_ text: String) {
        let query = text.trimmed
        guard query.count >= 2 else {
            completions = []
            completer.cancel()
            return
        }
        completer.queryFragment = query
    }

    func clear() {
        completions = []
        completer.cancel()
    }

    /// A picked completion resolved to its canonical "City, Country" form.
    /// The state is slotted in for the US and Canada, whose cities repeat
    /// across states ("Portland, OR, United States").
    func resolve(_ completion: MKLocalSearchCompletion) async -> String? {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        guard let item = try? await search.start().mapItems.first else { return nil }
        return Self.cityLine(from: item.placemark)
    }

    nonisolated static func cityLine(from placemark: CLPlacemark) -> String? {
        guard let city = placemark.locality ?? placemark.name, !city.isEmpty else { return nil }
        var parts = [city]
        if let code = placemark.isoCountryCode, code == "US" || code == "CA",
           let state = placemark.administrativeArea, !state.isEmpty {
            parts.append(state)
        }
        if let country = placemark.country, !country.isEmpty {
            parts.append(country)
        }
        return parts.joined(separator: ", ")
    }
}

extension CityAutocomplete: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            // On iOS 17 (no address filter) street results can slip in;
            // anything with a house number isn't a city.
            completions = results.filter { !$0.title.contains(where: \.isNumber) }.prefix(8).map { $0 }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Offline or throttled. The field keeps working as free text.
        Task { @MainActor in completions = [] }
    }
}

// MARK: - City field

/// A text field that offers city completions as you type. Tap a suggestion
/// and it lands as "City, Country" ("City, ST, Country" in the US/Canada);
/// keep typing and whatever you wrote is stored as-is. You can always save,
/// whether you're offline or typing a place Apple Maps has never heard of.
struct CityField: View {
    let title: String
    @Binding var text: String

    @StateObject private var autocomplete = CityAutocomplete()
    @FocusState private var focused: Bool
    // Suppresses the dropdown re-opening from the text change a pick causes.
    @State private var justPicked = false

    var body: some View {
        TextField(title, text: $text)
            .focused($focused)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .onChange(of: text) {
                guard focused, !justPicked else {
                    justPicked = false
                    return
                }
                autocomplete.search(text)
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { autocomplete.clear() }
            }

        if focused {
            ForEach(autocomplete.completions, id: \.self) { completion in
                Button {
                    pick(completion)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.footnote)
                            .foregroundStyle(Theme.aegean)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(completion.title)
                                .font(.callout)
                                .foregroundStyle(.primary)
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pick(_ completion: MKLocalSearchCompletion) {
        Task { @MainActor in
            // Resolving gives the canonical city/state/country; if the lookup
            // fails (offline between typing and tapping), fall back to the
            // completion's own text rather than losing the pick.
            let resolved = await autocomplete.resolve(completion)
            justPicked = true
            text = resolved ?? [completion.title, completion.subtitle]
                .filter { !$0.isEmpty }.joined(separator: ", ")
            autocomplete.clear()
            focused = false
        }
    }
}
