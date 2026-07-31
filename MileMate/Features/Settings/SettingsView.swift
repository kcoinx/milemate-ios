import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    @State private var cloudBackup = false

    var body: some View {
        List {
            profileSection

            settingsSection("Tracking") {
                destination("Tracking status", icon: "location.fill", tint: AppTheme.Color.brand) {
                    InformationView(
                        title: "Tracking",
                        icon: "location.fill",
                        message: "Automatic mileage tracking will be available in the next milestone."
                    )
                }
                destination("Vehicles", icon: "car.side.fill", tint: AppTheme.Color.brand) {
                    VehiclesView()
                }
                destination("Home address", icon: "house.fill", tint: .purple) {
                    AddressSettingsView(title: "Home Address", address: "1457 Pine Street")
                }
                destination("Work address", icon: "briefcase.fill", tint: .orange) {
                    AddressSettingsView(title: "Work Address", address: "425 Market Street")
                }
            }

            settingsSection("Notifications") {
                Toggle(isOn: $viewModel.smartReminders) {
                    settingLabel("Smart reminders", icon: "bell.badge.fill", tint: .orange)
                }
                Toggle(isOn: $viewModel.weeklySummary) {
                    settingLabel("Weekly summary", icon: "calendar.badge.clock", tint: AppTheme.Color.brand)
                }
            }

            settingsSection("Tax") {
                destination("IRS rate", icon: "dollarsign.circle.fill", tint: AppTheme.Color.positive) {
                    TaxSettingsView()
                }
                destination("Tax year", icon: "calendar", tint: .indigo) {
                    InformationView(title: "Tax Year", icon: "calendar", message: "MileMate is currently reporting for tax year 2026.")
                }
            }

            settingsSection("MileMate") {
                Toggle(isOn: $cloudBackup) {
                    settingLabel("Cloud backup", icon: "icloud.fill", tint: AppTheme.Color.brand)
                }
                Picker(selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) {
                        Text($0.rawValue).tag($0.rawValue)
                    }
                } label: {
                    settingLabel("Appearance", icon: "circle.lefthalf.filled", tint: .indigo)
                }
            }

            settingsSection("Privacy & Support") {
                destination("Privacy", icon: "hand.raised.fill", tint: .teal) {
                    InformationView(title: "Privacy", icon: "hand.raised.fill", message: "Your mileage data stays on this device in this milestone.")
                }
                destination("Help", icon: "questionmark.circle.fill", tint: AppTheme.Color.brand) {
                    InformationView(title: "Help", icon: "questionmark.circle.fill", message: "Find answers about trips, deductions, and tax-ready reports.")
                }
                destination("Support", icon: "lifepreserver.fill", tint: .orange) {
                    InformationView(title: "Support", icon: "lifepreserver.fill", message: "We are here to help you get the most from every mile.")
                }
                destination("Send feedback", icon: "bubble.left.and.bubble.right.fill", tint: .purple) {
                    InformationView(title: "Feedback", icon: "bubble.left.and.bubble.right.fill", message: "Tell us how MileMate can make your workday easier.")
                }
                destination("About MileMate", icon: "info.circle.fill", tint: AppTheme.Color.textSecondary) {
                    InformationView(title: "About MileMate", icon: "road.lanes", message: "Mileage clarity for people who drive for work.")
                }
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0 (1)").foregroundStyle(AppTheme.Color.textSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.Color.canvas)
        .navigationTitle("Settings")
    }

    private var profileSection: some View {
        Section {
            NavigationLink {
                ProfileSettingsView()
            } label: {
                HStack(spacing: AppTheme.Spacing.large) {
                    Text("AM")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(AppTheme.Color.brand.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Alex Morgan").font(.appTitle)
                        Text("Independent Consultant")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Color.textSecondary)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.small)
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            Text(title)
        }
    }

    private func settingLabel(_ title: String, icon: String, tint: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func destination<Destination: View>(
        _ title: String,
        icon: String,
        tint: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            settingLabel(title, icon: icon, tint: tint)
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("2024 Tesla Model Y").font(.headline)
                        Text("Midnight Silver - EV").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "car.side.fill").foregroundStyle(AppTheme.Color.brand)
                }
                .padding(.vertical, 8)
            }
            Button("Add another vehicle") {}
        }
        .navigationTitle("Vehicles")
    }
}

private struct AddressSettingsView: View {
    let title: String
    @State private var address: String

    init(title: String, address: String) {
        self.title = title
        _address = State(initialValue: address)
    }

    var body: some View {
        Form {
            Section("Saved location") {
                TextField("Address", text: $address)
                Label("Used to classify nearby trips", systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(title)
    }
}

private struct TaxSettingsView: View {
    @State private var deductionRate = 0.70
    @State private var taxRate = 28.0

    var body: some View {
        Form {
            Section("2026 rates") {
                LabeledContent("IRS mileage rate", value: deductionRate.formatted(.currency(code: "USD")) + " / mi")
                Stepper("Estimated tax rate: \(taxRate.formatted(.number))%", value: $taxRate, in: 0...60)
            }
            Section {
                Text("These estimates help calculate potential savings and do not constitute tax advice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("IRS Rate")
    }
}

private struct InformationView: View {
    let title: String
    let icon: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
