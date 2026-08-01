import SwiftUI

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue

    init(repository: any MileageRepository) {
        _viewModel = State(initialValue: SettingsViewModel(repository: repository))
    }

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
                destination("Frequent places", icon: "mappin.and.ellipse", tint: AppTheme.Color.brand) {
                    FrequentPlacesView(places: viewModel.frequentPlaces)
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
        .task { await viewModel.loadFrequentPlaces() }
        .onReceive(NotificationCenter.default.publisher(for: .mileageTripsDidChange)) { _ in
            Task { await viewModel.loadFrequentPlaces() }
        }
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
    @AppStorage("vehicle.nickname") private var nickname = "My Vehicle"
    @AppStorage("vehicle.year") private var year = "2024"
    @AppStorage("vehicle.make") private var make = "Tesla"
    @AppStorage("vehicle.model") private var model = "Model Y"

    var body: some View {
        Form {
            Section("Default vehicle") {
                TextField("Vehicle nickname", text: $nickname)
                TextField("Year", text: $year)
                    .keyboardType(.numberPad)
                TextField("Make", text: $make)
                TextField("Model", text: $model)
            }
            Section {
                Label("Trips are not linked to vehicles yet.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("This milestone supports one locally stored default vehicle.")
            }
        }
        .navigationTitle("Vehicle")
    }
}

private struct FrequentPlacesView: View {
    let places: [SettingsViewModel.FrequentPlace]
    @AppStorage("frequentPlace.home") private var home = ""
    @AppStorage("frequentPlace.work") private var work = ""

    var body: some View {
        Form {
            if places.isEmpty {
                Section {
                    Label(
                        "Complete trips to build your frequent-place history.",
                        systemImage: "mappin.slash"
                    )
                    .foregroundStyle(.secondary)
                }
            } else {
                Section("Confirmed labels") {
                    placePicker("Home", selection: $home, icon: "house.fill")
                    placePicker("Work", selection: $work, icon: "briefcase.fill")
                }

                Section("Most visited") {
                    ForEach(places.prefix(5)) { place in
                        LabeledContent(place.name, value: "\(place.visitCount) visits")
                    }
                }

                Section {
                    Text("Labels are saved only after you choose them. MileMate does not automatically infer Home or Work.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Frequent Places")
    }

    private func placePicker(
        _ title: String,
        selection: Binding<String>,
        icon: String
    ) -> some View {
        Picker(selection: selection) {
            Text("Not set").tag("")
            ForEach(places) { place in
                Text(place.name).tag(place.name)
            }
        } label: {
            Label(title, systemImage: icon)
        }
    }
}

private struct TaxSettingsView: View {
    @AppStorage(MileageSettings.rateKey) private var deductionRate = MileageSettings.defaultMileageRate
    @AppStorage(MileageSettings.taxRateKey) private var taxRate = MileageSettings.defaultTaxRate

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
