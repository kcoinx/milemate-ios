import SwiftUI

struct TripsView: View {
    private let repository: any MileageRepository
    @State private var viewModel: TripsViewModel
    @State private var hasAppeared = false
    @State private var tripPendingDeletion: Trip?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(repository: any MileageRepository) {
        self.repository = repository
        _viewModel = State(initialValue: TripsViewModel(repository: repository))
    }

    var body: some View {
        List {
            overview
                .tripListRow()
            filters
                .tripListRow()

            if viewModel.filteredTrips.isEmpty {
                emptyState
                    .tripListRow()
            } else {
                ForEach(Array(viewModel.filteredTrips.enumerated()), id: \.element.id) { index, trip in
                    NavigationLink(value: trip) {
                        premiumTripCard(trip)
                    }
                    .buttonStyle(.plain)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 14)
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.4).delay(Double(index) * 0.05),
                        value: hasAppeared
                    )
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        classificationAction(.business, trip: trip, tint: AppTheme.Color.brand)
                        classificationAction(.personal, trip: trip, tint: AppTheme.Color.warning)
                        classificationAction(.unclassified, trip: trip, tint: .gray)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            tripPendingDeletion = trip
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .tripListRow()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.Color.canvas)
        .navigationTitle("Trips")
        .onAppear {
            hasAppeared = true
            Task { await viewModel.load() }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search destinations")
        .navigationDestination(for: Trip.self) { TripDetailView(trip: $0, repository: repository) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {}) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Trip filters")
            }
        }
        .confirmationDialog(
            "Delete this trip?",
            isPresented: Binding(
                get: { tripPendingDeletion != nil },
                set: { if !$0 { tripPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Trip", role: .destructive) {
                guard let trip = tripPendingDeletion else { return }
                tripPendingDeletion = nil
                Task { await viewModel.delete(trip) }
            }
            Button("Cancel", role: .cancel) { tripPendingDeletion = nil }
        } message: {
            Text("This trip will be removed from your mileage records.")
        }
        .alert(
            "Trips unavailable",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var overview: some View {
        AppCard {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TOTAL MILEAGE")
                        .font(.caption.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(AppTheme.Color.textSecondary)
                    Text(viewModel.totalMiles.milesFormatted)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("\(viewModel.filteredTrips.count) recorded trips")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Color.textSecondary)
                }
                Spacer()
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.Color.brand)
                    .frame(width: 54, height: 54)
                    .background(AppTheme.Color.brand.opacity(0.12), in: Circle())
            }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.small) {
                filterButton("All", selection: nil)
                ForEach(Trip.Classification.allCases, id: \.self) { item in
                    filterButton(item.rawValue, selection: item)
                }
            }
        }
    }

    private func premiumTripCard(_ trip: Trip) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                if !trip.route.isEmpty {
                    RouteMapView(
                        origin: trip.originName,
                        destination: trip.destinationName,
                        route: trip.route,
                        height: 148,
                        interactive: false
                    )
                }

                HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
                    VStack(spacing: 3) {
                        Circle().fill(AppTheme.Color.textSecondary).frame(width: 8, height: 8)
                        Rectangle().fill(AppTheme.Color.divider).frame(width: 1, height: 25)
                        Circle().fill(AppTheme.Color.brand).frame(width: 8, height: 8)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(trip.originName)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Color.textSecondary)
                        Text(trip.destinationName)
                            .font(.appHeadline)
                    }
                    Spacer(minLength: AppTheme.Spacing.small)
                    ClassificationBadge(classification: trip.classification)
                }

                Divider()

                HStack {
                    tripValue("DISTANCE", value: trip.distanceMiles.milesFormatted)
                    Spacer()
                    tripValue("EST. DEDUCTION", value: trip.estimatedDeduction.currencyFormatted, tint: AppTheme.Color.positive)
                    Spacer()
                    tripValue("DATE", value: trip.startedAt.shortDisplay)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func tripValue(_ label: String, value: String, tint: Color = AppTheme.Color.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.Color.textSecondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Trips Yet", systemImage: "car.side")
        } description: {
            Text("Start your first manual trip to begin tracking mileage and estimated tax deductions.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    private func filterButton(_ title: String, selection: Trip.Classification?) -> some View {
        let isSelected = viewModel.selection == selection
        return Button(title) { viewModel.selection = selection }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : AppTheme.Color.textPrimary)
            .padding(.horizontal, 17)
            .frame(minHeight: 42)
            .background(isSelected ? AppTheme.Color.brand : AppTheme.Color.surface, in: Capsule())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isSelected)
    }

    private func classificationAction(
        _ classification: Trip.Classification,
        trip: Trip,
        tint: Color
    ) -> some View {
        Button {
            Task { await viewModel.classify(trip, as: classification) }
        } label: {
            Label(classification.rawValue, systemImage: classification.systemImage)
        }
        .tint(tint)
    }
}

private extension View {
    func tripListRow() -> some View {
        listRowInsets(
            EdgeInsets(
                top: AppTheme.Spacing.small,
                leading: AppTheme.Spacing.large,
                bottom: AppTheme.Spacing.small,
                trailing: AppTheme.Spacing.large
            )
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

private extension Trip.Classification {
    var systemImage: String {
        switch self {
        case .business: "briefcase.fill"
        case .personal: "person.fill"
        case .unclassified: "questionmark"
        }
    }
}
