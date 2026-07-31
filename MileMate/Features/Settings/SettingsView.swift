import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        List {
            profileSection
            trackingSection
            appearanceSection
            supportSection
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0 (1)").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .preferredColorScheme(viewModel.colorScheme)
    }

    private var profileSection: some View {
        Section {
            NavigationLink {
                ProfileSettingsView()
            } label: {
                HStack(spacing: AppTheme.Spacing.medium) {
                    Text("AM")
                        .font(.appHeadline)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.Color.brand.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Alex Morgan").font(.headline)
                        Text("Independent Consultant").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var trackingSection: some View {
        Section("Mileage") {
            NavigationLink("Vehicles") { VehiclesView() }
            NavigationLink("Deduction & tax rates") { TaxSettingsView() }
            Toggle("Smart reminders", isOn: $viewModel.smartReminders)
            Toggle("Weekly summary", isOn: $viewModel.weeklySummary)
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $viewModel.appearance) {
                ForEach(SettingsViewModel.Appearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
        }
    }

    private var supportSection: some View {
        Section("Support") {
            NavigationLink("Privacy & data") { InformationView(title: "Privacy & Data", message: "Your trip data is currently stored locally on this device.") }
            NavigationLink("Help center") { InformationView(title: "Help Center", message: "Find answers about mileage classifications, reports, and deductions.") }
            NavigationLink("About MileMate") { InformationView(title: "About MileMate", message: "Mileage clarity for people who drive for work.") }
        }
    }
}

private struct ProfileSettingsView: View {
    @State private var name = "Alex Morgan"
    @State private var occupation = "Independent Consultant"
    var body: some View {
        Form {
            Section("Personal details") {
                TextField("Name", text: $name)
                TextField("Occupation", text: $occupation)
            }
        }
        .navigationTitle("Profile")
    }
}

private struct VehiclesView: View {
    var body: some View {
        List {
            Section("Primary vehicle") {
                Label {
                    VStack(alignment: .leading) {
                        Text("2024 Tesla Model Y")
                        Text("Midnight Silver • EV").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "car.side.fill").foregroundStyle(AppTheme.Color.brand)
                }
            }
            Button("Add another vehicle") {}
        }
        .navigationTitle("Vehicles")
    }
}

private struct TaxSettingsView: View {
    @State private var deductionRate = 0.70
    @State private var taxRate = 28.0
    var body: some View {
        Form {
            Section("2026 rates") {
                LabeledContent("Mileage rate", value: deductionRate.formatted(.currency(code: "USD")) + " / mi")
                Stepper("Estimated tax rate: \(taxRate.formatted(.number))%", value: $taxRate, in: 0...60)
            }
            Section {
                Text("These estimates help calculate potential savings and do not constitute tax advice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Tax Rates")
    }
}

private struct InformationView: View {
    let title: String
    let message: String
    var body: some View {
        ContentUnavailableView(title, systemImage: "checkmark.shield.fill", description: Text(message))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
