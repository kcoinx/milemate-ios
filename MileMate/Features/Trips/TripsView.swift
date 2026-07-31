import SwiftUI

struct TripsView: View {
    @State private var viewModel = TripsViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                summary
                filters
                AppCard {
                    ForEach(Array(viewModel.filteredTrips.enumerated()), id: \.element.id) { index, trip in
                        NavigationLink(value: trip) {
                            TripRow(trip: trip)
                        }
                        .buttonStyle(.plain)
                        if index < viewModel.filteredTrips.count - 1 { Divider() }
                    }
                }
            }
            .padding(AppTheme.Spacing.large)
        }
        .background(AppTheme.Color.canvas)
        .navigationTitle("Trips")
        .searchable(text: $viewModel.searchText, prompt: "Search trips")
        .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {}) { Image(systemName: "plus") }
                    .accessibilityLabel("Add trip")
            }
        }
    }

    private var summary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.totalMiles.milesFormatted)
                    .font(.appMetric)
                Text("\(viewModel.filteredTrips.count) trips shown")
                    .foregroundStyle(AppTheme.Color.textSecondary)
            }
            Spacer()
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.title2)
                .foregroundStyle(AppTheme.Color.brand)
                .padding()
                .background(AppTheme.Color.brand.opacity(0.1), in: Circle())
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                filterButton("All", selection: nil)
                ForEach(Trip.Classification.allCases, id: \.self) { item in
                    filterButton(item.rawValue, selection: item)
                }
            }
        }
    }

    private func filterButton(_ title: String, selection: Trip.Classification?) -> some View {
        let isSelected = viewModel.selection == selection
        return Button(title) { viewModel.selection = selection }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : AppTheme.Color.textPrimary)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(isSelected ? AppTheme.Color.brand : AppTheme.Color.surface, in: Capsule())
    }
}

