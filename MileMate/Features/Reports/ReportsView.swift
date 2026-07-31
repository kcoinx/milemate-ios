import SwiftUI

struct ReportsView: View {
    @State private var viewModel: ReportsViewModel
    @State private var showingExport = false
    @State private var selectedExport = "PDF"

    init(repository: any MileageRepository) {
        _viewModel = State(initialValue: ReportsViewModel(repository: repository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                Picker("Reporting period", selection: $viewModel.period) {
                    ForEach(ReportsViewModel.Period.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)

                monthlySummary

                SectionHeader(title: "Quick actions")
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: AppTheme.Spacing.medium) {
                    actionCard("Export PDF", icon: "doc.richtext", tint: AppTheme.Color.brand)
                    actionCard("Export CSV", icon: "tablecells", tint: AppTheme.Color.positive)
                    actionCard("IRS Mileage Report", icon: "building.columns", tint: AppTheme.Color.warning)
                    actionCard("Year Summary", icon: "calendar", tint: AppTheme.Color.textPrimary)
                }

                yearSummary
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.bottom, AppTheme.Spacing.xxLarge)
        }
        .background(AppTheme.Color.canvas)
        .navigationTitle("Reports")
        .onAppear { Task { await viewModel.load() } }
        .confirmationDialog("Export \(selectedExport)", isPresented: $showingExport) {
            Button("Save to Files") {}
            Button("Share") {}
            Button("Cancel", role: .cancel) {}
        }
    }

    private var monthlySummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date.now.formatted(.dateTime.month(.wide).year()).uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Tax summary")
                        .font(.title2.weight(.bold))
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("ESTIMATED IRS DEDUCTION")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(viewModel.summary.estimatedDeduction.currencyFormatted)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.75)
            }

            HStack {
                reportMetric("BUSINESS MILES", value: viewModel.summary.businessMiles.milesFormatted)
                Spacer()
                reportMetric("EST. TAX SAVINGS", value: viewModel.summary.estimatedTaxSavings.currencyFormatted)
            }
        }
        .foregroundStyle(.white)
        .padding(AppTheme.Spacing.xLarge)
        .background {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.30, blue: 0.20), AppTheme.Color.brand],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 30))
        }
        .shadow(color: AppTheme.Color.brand.opacity(0.22), radius: 24, y: 14)
        .accessibilityElement(children: .combine)
    }

    private func actionCard(_ title: String, icon: String, tint: Color) -> some View {
        Button {
            selectedExport = title
            showingExport = true
        } label: {
            AppCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(tint)
                        .frame(width: 48, height: 48)
                        .background(tint.opacity(0.12), in: Circle())
                    Text(title)
                        .font(.appHeadline)
                        .foregroundStyle(AppTheme.Color.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text("COMING SOON")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(AppTheme.Color.textSecondary)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var yearSummary: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                SectionHeader(title: "2026 at a glance")
                summaryRow("Business mileage", value: viewModel.summary.businessMiles.milesFormatted)
                Divider()
                summaryRow("Recorded trips", value: "\(viewModel.summary.tripCount)")
                Divider()
                summaryRow("Deduction rate", value: MileageSettings.mileageRate.formatted(.currency(code: "USD")) + " / mile")
                Divider()
                summaryRow("Estimated savings", value: viewModel.summary.estimatedTaxSavings.currencyFormatted, emphasized: true)
            }
        }
    }

    private func reportMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.headline.monospacedDigit())
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
