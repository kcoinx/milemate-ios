import Charts
import SwiftUI

struct ReportsView: View {
    private struct ExportedReport: Identifiable {
        let url: URL
        var id: URL { url }
    }

    @State private var viewModel: ReportsViewModel
    @State private var isGeneratingPDF = false
    @State private var exportedReport: ExportedReport?
    @State private var exportErrorMessage: String?

    init(repository: any MileageRepository) {
        _viewModel = State(initialValue: ReportsViewModel(repository: repository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                Picker("Reporting period", selection: $viewModel.period) {
                    ForEach(ReportsViewModel.Period.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)

                vehiclePicker
                monthlySummary
                mileageChart
                if viewModel.selectedVehicleID == nil && viewModel.vehicleBreakdown.count > 1 {
                    vehicleBreakdown
                }

                SectionHeader(title: "Quick actions")
                quickActions

                yearSummary
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.bottom, AppTheme.Spacing.xxLarge)
        }
        .background(AppTheme.Color.canvas)
        .navigationTitle("Reports")
        .onAppear { Task { await viewModel.load() } }
        .onReceive(NotificationCenter.default.publisher(for: .mileageTripsDidChange)) { _ in
            Task { await viewModel.load() }
        }
        .sheet(item: $exportedReport) { report in
            ActivityShareSheet(items: [report.url]) {
                removeTemporaryReport(report.url)
                exportedReport = nil
            }
        }
        .alert(
            "Unable to Export PDF",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { exportErrorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    private var vehiclePicker: some View {
        Menu {
            Button("All Vehicles") { viewModel.selectedVehicleID = nil }
            ForEach(viewModel.vehicles) { vehicle in
                Button(vehicle.nickname) { viewModel.selectedVehicleID = vehicle.id }
            }
        } label: {
            Label(
                viewModel.vehicles.first(where: { $0.id == viewModel.selectedVehicleID })?.nickname
                    ?? "All Vehicles",
                systemImage: "car.side.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.Color.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.large)
            .background(AppTheme.Color.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        }
    }

    private var vehicleBreakdown: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                SectionHeader(title: "Business miles by vehicle")
                ForEach(viewModel.vehicleBreakdown) { item in
                    LabeledContent(item.vehicle, value: item.miles.milesFormatted)
                    if item.id != viewModel.vehicleBreakdown.last?.id { Divider() }
                }
            }
        }
    }

    private var monthlySummary: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summaryPeriodTitle.uppercased())
                            .font(.caption.weight(.bold))
                            .tracking(1.1)
                            .foregroundStyle(AppTheme.Color.textSecondary)
                        Text("Monthly Summary")
                            .font(.appTitle)
                    }
                    Spacer()
                    Image(systemName: "chart.bar.doc.horizontal.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.Color.brand)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.Color.brand.opacity(0.12), in: Circle())
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("BUSINESS MILES")
                        .font(.caption.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(AppTheme.Color.textSecondary)
                    Text(viewModel.summary.businessMiles.milesFormatted)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Color.brand)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: AppTheme.Spacing.xLarge) {
                    GridRow {
                        reportMetric(
                            "ESTIMATED DEDUCTION",
                            value: viewModel.summary.estimatedDeduction.currencyFormatted
                        )
                        reportMetric(
                            "RECORDED TRIPS",
                            value: "\(viewModel.summary.tripCount)"
                        )
                    }
                    GridRow {
                        reportMetric(
                            "IRS RATE",
                            value: MileageSettings.mileageRate.formatted(.currency(code: "USD"))
                                + " / mile",
                            isReference: true
                        )
                        Color.clear
                    }
                }

                Label(
                    viewModel.summary.businessMiles > 0
                        ? "Estimated deduction is based on your business miles and configured mileage rate."
                        : "Only Business trips contribute to your estimated deduction.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(AppTheme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var quickActions: some View {
        AppCard {
            VStack(spacing: AppTheme.Spacing.large) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
                    Button {
                        generatePDF()
                    } label: {
                        exportPDFActionCell
                    }
                    .buttonStyle(.plain)
                    .disabled(isGeneratingPDF)
                    Divider()
                    actionCell("Export CSV", icon: "tablecells", tint: AppTheme.Color.positive)
                }
                Divider()
                HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
                    actionCell("IRS Mileage Report", icon: "building.columns", tint: AppTheme.Color.warning)
                    Divider()
                    actionCell("Year Summary", icon: "calendar", tint: AppTheme.Color.textPrimary)
                }
            }
        }
    }

    private var exportPDFActionCell: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Group {
                if isGeneratingPDF {
                    ProgressView()
                } else {
                    Image(systemName: "doc.richtext")
                        .font(.title3.weight(.semibold))
                }
            }
            .foregroundStyle(AppTheme.Color.brand)
            .frame(width: 40, height: 40)
            .background(AppTheme.Color.brand.opacity(0.12), in: Circle())

            Text("Export PDF")
                .font(.appHeadline)
                .foregroundStyle(AppTheme.Color.textPrimary)
            Text(isGeneratingPDF ? "GENERATING..." : "PREVIEW & SHARE")
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(AppTheme.Color.brand)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isGeneratingPDF ? "Generating PDF report" : "Export PDF, preview and share"
        )
    }

    private func generatePDF() {
        guard !isGeneratingPDF else { return }
        isGeneratingPDF = true
        exportErrorMessage = nil
        Task {
            await viewModel.load()
            do {
                let report = try viewModel.preparePDFReport()
                let url = try MileagePDFRenderer().render(report)
                exportedReport = ExportedReport(url: url)
            } catch {
                exportErrorMessage = error.localizedDescription
            }
            isGeneratingPDF = false
        }
    }

    private func removeTemporaryReport(_ url: URL) {
        guard url.deletingLastPathComponent() == FileManager.default.temporaryDirectory else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    private var mileageChart: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                SectionHeader(title: "Business mileage by week")

                if viewModel.weeklyMileage.isEmpty {
                    Label {
                        Text("Record and classify business trips to see weekly mileage.")
                            .foregroundStyle(AppTheme.Color.textSecondary)
                    } icon: {
                        Image(systemName: "chart.bar.xaxis")
                            .foregroundStyle(AppTheme.Color.brand)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityElement(children: .combine)
                } else {
                    Chart(viewModel.weeklyMileage) { item in
                        BarMark(
                            x: .value("Week", item.weekStart, unit: .weekOfYear),
                            y: .value("Business miles", item.miles)
                        )
                        .foregroundStyle(AppTheme.Color.brand.gradient)
                        .cornerRadius(5)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(AppTheme.Color.divider.opacity(0.3))
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) {
                            AxisGridLine().foregroundStyle(AppTheme.Color.divider.opacity(0.3))
                            AxisValueLabel()
                        }
                    }
                    .frame(height: 190)
                    .accessibilityLabel("Business mileage by week")
                }
            }
        }
    }

    private func actionCell(_ title: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: Circle())
            Text(title)
                .font(.appHeadline)
                .foregroundStyle(AppTheme.Color.textPrimary)
                .multilineTextAlignment(.leading)
            Text("COMING SOON")
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(AppTheme.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), coming soon")
    }

    private var yearSummary: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                SectionHeader(title: "2026 at a glance")
                summaryRow("Business Mileage", value: viewModel.summary.businessMiles.milesFormatted)
                Divider()
                summaryRow("Recorded Trips", value: "\(viewModel.summary.tripCount)")
                Divider()
                summaryRow("Deduction Rate", value: MileageSettings.mileageRate.formatted(.currency(code: "USD")) + " / mile")
                Divider()
                summaryRow("Estimated Deduction", value: viewModel.summary.estimatedDeduction.currencyFormatted, emphasized: true)
            }
        }
    }

    private func reportMetric(
        _ title: String,
        value: String,
        isReference: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(
                    isReference
                        ? .subheadline.weight(.semibold).monospacedDigit()
                        : .headline.weight(.semibold).monospacedDigit()
                )
                .foregroundStyle(AppTheme.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var summaryPeriodTitle: String {
        switch viewModel.period {
        case .month:
            return Date.now.formatted(.dateTime.month(.wide).year())
        case .quarter:
            let quarter = (Calendar.current.component(.month, from: .now) - 1) / 3 + 1
            return "Quarter \(quarter), \(Calendar.current.component(.year, from: .now))"
        case .year:
            return Date.now.formatted(.dateTime.year())
        }
    }

    private func summaryRow(_ title: String, value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(AppTheme.Color.textSecondary)
            Spacer()
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(emphasized ? AppTheme.Color.positive : AppTheme.Color.textPrimary)
        }
    }
}
