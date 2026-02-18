
import SwiftUI

struct CountryPickerView: View {
    @Binding var selectedCountryCode: String
    let countries: [(code: String, name: String)]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    
    private var filteredCountries: [(code: String, name: String)] {
        if searchText.isEmpty {
            return countries
        }
        return countries.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(filteredCountries, id: \.code) { country in
                    Button {
                        selectedCountryCode = country.code
                        dismiss()
                    } label: {
                        HStack {
                            Text(country.name)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedCountryCode == country.code {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search country")
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
}

