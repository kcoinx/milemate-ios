import SwiftUI

struct TripsView: View {
    private let repository: any MileageRepository
    @State private var viewModel: TripsViewModel
    @State private var hasAppeared = false

    init(repository: any MileageRepository) {
        self.repository = repository
        _viewModel = State(initialValue: TripsViewModel(repository: repository))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                overview
                filters

                if viewModel.filteredTrips.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(viewModel.filteredTrips.enumerated()), id: \.element.id) { index, trip in
                        NavigationLink(value: trip) {
                            premiumTripCard(trip)
                        }
                        .buttonStyle(.plain)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 14)
                        .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.05), value: hasAppeared)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.bottom, AppTheme.Spacing.xxLarge)
        }
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
            Text("Start driving and MileMate will automatically detect your first trip.")
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
            .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
