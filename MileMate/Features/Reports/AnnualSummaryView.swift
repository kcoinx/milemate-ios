import Charts
import Observation
import SwiftUI

@MainActor
@Observable
final class AnnualSummaryViewModel {
    private let repository: any MileageRepository
    private let vehicleID: UUID?
    private(set) var trips: [Trip] = []
    var selectedYear: Int

    init(
        repository: any MileageRepository,
        initialYear: Int,
        vehicleID: UUID?
    ) {
        self.repository = repository
        self.selectedYear = initialYear
        self.vehicleID = vehicleID
    }

    var availableYears: [Int] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: .now)
        let years = Set(
            trips.map { trip in
                calendar.component(.year, from: trip.startedAt)
            } + [currentYear, selectedYear]
        )
        return years.sorted { first, second in first > second }
    }

    var summary: AnnualMileageSummary {
        MileageReportPreparationService.annualSummary(
            trips: trips,
            year: selectedYear,
            vehicleID: vehicleID,
            mileageRate: MileageSettings.mileageRate
        )
    }

    func load() async {
        trips = (try? await repository.fetchTrips()) ?? []
    }
}

struct AnnualSummaryView: View {
    @State private var viewModel: AnnualSummaryViewModel

    init(
        repository: any MileageRepository,
        initialYear: Int,
        vehicleID: UUID?
    ) {
        _viewModel = State(
            initialValue: AnnualSummaryViewModel(
                repository: repository,
                initialYear: initialYear,
                vehicleID: vehicleID
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                yearPicker
                overview
                monthlyMileage

                if viewModel.summary.vehicleBreakdown.count > 1 {
                    vehicleBreakdown
                }
                if shouldShowMileageSplit {
                    mileageSplit
                }
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.bottom, AppTheme.Spacing.xxLarge)
        }
        .background(AppTheme.Color.canvas)
        .navigationTitle("Annual Summary")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .onReceive(NotificationCenter.default.publisher(for: .mileageTripsDidChange)) { _ in
            Task { await viewModel.load() }
        }
    }

    private var yearPicker: some View {
        Menu {
            ForEach(viewModel.availableYears, id: \.self) { year in
                Button("\(year)") { viewModel.selectedYear = year }
            }
        } label: {
            HStack {
                Label("Tax Year", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(viewModel.selectedYear)")
                    .font(.headline.monospacedDigit())
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(AppTheme.Color.textPrimary)
            .frame(minHeight: 44)
            .padding(.horizontal, AppTheme.Spacing.large)
            .background(
                AppTheme.Color.surface,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
            )
        }
    }

    private var overview: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                SectionHeader(title: "\(viewModel.selectedYear) overview")

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                    Text("BUSINESS MILES")
                        .font(.caption.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(AppTheme.Color.textSecondary)
                    Text(viewModel.summary.businessMiles.milesFormatted)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Color.brand)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: AppTheme.Spacing.large) {
                    GridRow {
                        metric(
                            "BUSINESS TRIPS",
                            value: "\(viewModel.summary.businessTrips)"
                        )
                        metric(
                            "ESTIMATED DEDUCTION",
                            value: viewModel.summary.estimatedDeduction.currencyFormatted
                        )
                    }
                    Divider()
                    GridRow {
                        metric(
                            "MILEAGE RATE",
                            value: viewModel.summary.mileageRate.formatted(
                                .currency(code: "USD")
                            ) + " / mile"
                        )
                        metric(
                            "AVERAGE TRIP",
                            value: viewModel.summary.averageBusinessTripDistance.milesFormatted
                        )
                    }
                    Divider()
                    GridRow {
                        metric(
                            "MOST ACTIVE MONTH",
                            value: viewModel.summary.mostActiveMonth ?? "Not available"
                        )
                        metric(
                            "PRIMARY VEHICLE",
                            value: viewModel.summary.primaryVehicle ?? "Not available"
                        )
                    }
                }

                if viewModel.summary.businessTrips == 0 {
                    Label(
                        "Complete and classify Business trips to build your annual mileage summary.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var monthlyMileage: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                SectionHeader(title: "Monthly business mileage")
                Chart(viewModel.summary.monthlyMileage) { item in
                    BarMark(
                        x: .value("Month", item.label),
                        y: .value("Business miles", item.miles)
                    )
                    .foregroundStyle(AppTheme.Color.brand.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 190)
                .accessibilityLabel(
                    "Monthly business mileage for \(viewModel.selectedYear)"
                )
            }
        }
    }

    private var vehicleBreakdown: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                SectionHeader(title: "Business miles by vehicle")
                ForEach(viewModel.summary.vehicleBreakdown) { item in
                    LabeledContent {
                        Text(item.miles.milesFormatted)
                            .font(.headline.monospacedDigit())
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.vehicle)
                            Text("\(item.trips) Business trips")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Color.textSecondary)
                        }
                    }
                    if item.id != viewModel.summary.vehicleBreakdown.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var mileageSplit: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                SectionHeader(title: "Mileage split")
                HStack(spacing: AppTheme.Spacing.large) {
                    splitMetric(
                        "Business",
                        miles: viewModel.summary.businessMiles,
                        color: AppTheme.Color.brand
                    )
                    Divider()
                    splitMetric(
                        "Personal",
                        miles: viewModel.summary.personalMiles,
                        color: AppTheme.Color.textSecondary
                    )
                }
            }
        }
    }

    private var shouldShowMileageSplit: Bool {
        viewModel.summary.businessMiles > 0 &&
        viewModel.summary.personalMiles > 0
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func splitMetric(
        _ title: String,
        miles: Double,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Color.textSecondary)
            Text(miles.milesFormatted)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
