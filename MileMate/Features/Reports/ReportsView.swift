import Charts
import SwiftUI

struct ReportsView: View {
    @State private var viewModel: ReportsViewModel
    @State private var showingExport = false

    init(repository: any MileageRepository) {
        _viewModel = State(initialValue: ReportsViewModel(repository: repository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                Picker("Reporting period", selection: $viewModel.period) {
                    ForEach(ReportsViewModel.Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                AppCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                        Label("2026 mileage report", systemImage: "doc.text.fill")
                            .font(.appHeadline)
                            .foregroundStyle(AppTheme.Color.brand)
                        Text(viewModel.summary.estimatedDeduction.currencyFormatted)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("Potential business mileage deduction")
                            .foregroundStyle(AppTheme.Color.textSecondary)
                        Divider()
                        HStack {
                            reportMetric("Business", value: viewModel.summary.businessMiles.milesFormatted)
                            Spacer()
                            reportMetric("Personal", value: viewModel.summary.personalMiles.milesFormatted)
                            Spacer()
                            reportMetric("Trips", value: "\(viewModel.summary.tripCount)")
                        }
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                        SectionHeader(title: "Mileage by month")
                        Chart(viewModel.summary.monthlyMiles) { item in
                            AreaMark(x: .value("Month", item.month), y: .value("Miles", item.miles))
                                .foregroundStyle(AppTheme.Color.brand.opacity(0.16))
                            LineMark(x: .value("Month", item.month), y: .value("Miles", item.miles))
                                .foregroundStyle(AppTheme.Color.brand)
                                .lineStyle(.init(lineWidth: 3, lineCap: .round))
                            PointMark(x: .value("Month", item.month), y: .value("Miles", item.miles))
                                .foregroundStyle(AppTheme.Color.brand)
                        }
                        .frame(height: 210)
                    }
                }

                Button { showingExport = true } label: {
                    Label("Export tax-ready report", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.Color.brand)
            }
            .padding(AppTheme.Spacing.large)
        }
        .background(AppTheme.Color.canvas)
        .navigationTitle("Reports")
        .task { await viewModel.load() }
        .confirmationDialog("Export report", isPresented: $showingExport) {
            Button("PDF summary") {}
            Button("CSV trip log") {}
            Button("Share with accountant") {}
        }
    }

    private func reportMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(AppTheme.Color.textSecondary)
        }
    }
}
