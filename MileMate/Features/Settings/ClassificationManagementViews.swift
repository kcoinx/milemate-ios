import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
private final class VehicleManagementViewModel {
    let repository: any MileageRepository
    private(set) var vehicles: [Vehicle] = []
    var editingVehicle: Vehicle?
    var deletingVehicle: Vehicle?
    var errorMessage: String?

    init(repository: any MileageRepository) {
        self.repository = repository
    }

    func load() async {
        do {
            vehicles = try await repository.fetchVehicles()
            errorMessage = nil
        } catch {
            errorMessage = "Vehicles are temporarily unavailable."
        }
    }

    func save(_ vehicle: Vehicle) async {
        do {
            try await repository.saveVehicle(vehicle)
            await load()
            NotificationCenter.default.post(name: .mileageVehiclesDidChange, object: vehicle.id)
        } catch {
            errorMessage = "The vehicle could not be saved."
        }
    }

    func setDefault(_ vehicle: Vehicle) async {
        var updated = vehicle
        updated.isDefault = true
        updated.updatedAt = .now
        await save(updated)
    }

    func delete(_ vehicle: Vehicle, reassignTo replacement: Vehicle?) async {
        do {
            try await repository.deleteVehicle(id: vehicle.id, reassignTo: replacement)
            await load()
            NotificationCenter.default.post(name: .mileageVehiclesDidChange, object: vehicle.id)
            NotificationCenter.default.post(name: .mileageTripsDidChange, object: nil)
        } catch {
            errorMessage = "The vehicle could not be deleted."
        }
    }
}

struct VehicleManagementView: View {
    @State private var viewModel: VehicleManagementViewModel
    @State private var showingAddVehicle = false

    init(repository: any MileageRepository) {
        _viewModel = State(initialValue: VehicleManagementViewModel(repository: repository))
    }

    var body: some View {
        List {
            ForEach(viewModel.vehicles) { vehicle in
                Button {
                    viewModel.editingVehicle = vehicle
                } label: {
                    HStack(spacing: AppTheme.Spacing.medium) {
                        Image(systemName: "car.side.fill")
                            .foregroundStyle(AppTheme.Color.brand)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(vehicle.nickname).font(.headline)
                                if vehicle.isDefault {
                                    Text("Default")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.Color.brand)
                                }
                            }
                            if !vehicle.detail.isEmpty {
                                Text(vehicle.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Color.textSecondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(AppTheme.Color.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if !vehicle.isDefault {
                        Button {
                            Task { await viewModel.setDefault(vehicle) }
                        } label: {
                            Label("Set Default", systemImage: "checkmark.circle")
                        }
                        .tint(AppTheme.Color.brand)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        viewModel.deletingVehicle = vehicle
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .settingsDetailScrollBehavior()
        .scrollIndicators(.hidden)
        .navigationTitle("Vehicles")
        .toolbar {
            Button {
                showingAddVehicle = true
            } label: {
                Label("Add Vehicle", systemImage: "plus")
            }
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $showingAddVehicle) {
            VehicleEditorView(vehicle: nil) { vehicle in
                Task { await viewModel.save(vehicle) }
            }
        }
        .sheet(item: $viewModel.editingVehicle) { vehicle in
            VehicleEditorView(vehicle: vehicle) { editedVehicle in
                Task { await viewModel.save(editedVehicle) }
            }
        }
        .confirmationDialog(
            "Delete this vehicle?",
            isPresented: Binding(
                get: { viewModel.deletingVehicle != nil },
                set: { isPresented in
                    if !isPresented { viewModel.deletingVehicle = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            if let deleting = viewModel.deletingVehicle {
                Button("Keep Historical Trip Information", role: .destructive) {
                    viewModel.deletingVehicle = nil
                    Task { await viewModel.delete(deleting, reassignTo: nil) }
                }
                ForEach(
                    viewModel.vehicles.filter { vehicle in vehicle.id != deleting.id }
                ) { replacement in
                    Button("Reassign to \(replacement.nickname)") {
                        viewModel.deletingVehicle = nil
                        Task { await viewModel.delete(deleting, reassignTo: replacement) }
                    }
                }
            }
            Button("Cancel", role: .cancel) { viewModel.deletingVehicle = nil }
        } message: {
            Text("Historical trips can retain this vehicle snapshot or be reassigned to another vehicle.")
        }
    }
}

private struct VehicleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let original: Vehicle?
    let onSave: (Vehicle) -> Void
    @State private var nickname: String
    @State private var year: String
    @State private var make: String
    @State private var model: String
    @State private var plate: String
    @State private var isDefault: Bool

    init(vehicle: Vehicle?, onSave: @escaping (Vehicle) -> Void) {
        original = vehicle
        self.onSave = onSave
        _nickname = State(initialValue: vehicle?.nickname ?? "")
        _year = State(initialValue: vehicle?.year.map { year in String(year) } ?? "")
        _make = State(initialValue: vehicle?.make ?? "")
        _model = State(initialValue: vehicle?.model ?? "")
        _plate = State(initialValue: vehicle?.licensePlateNickname ?? "")
        _isDefault = State(initialValue: vehicle?.isDefault ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nickname", text: $nickname)
                TextField("Year", text: $year).keyboardType(.numberPad)
                TextField("Make", text: $make)
                TextField("Model", text: $model)
                TextField("License plate nickname (optional)", text: $plate)
                Toggle("Default vehicle", isOn: $isDefault)
            }
            .settingsDetailScrollBehavior()
            .scrollIndicators(.hidden)
            .navigationTitle(original == nil ? "Add Vehicle" : "Edit Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            Vehicle(
                                id: original?.id ?? UUID(),
                                nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                                year: Int(year),
                                make: make.trimmingCharacters(in: .whitespacesAndNewlines),
                                model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                                licensePlateNickname: plate.trimmingCharacters(in: .whitespacesAndNewlines),
                                isDefault: isDefault,
                                createdAt: original?.createdAt ?? .now,
                                updatedAt: .now
                            )
                        )
                        dismiss()
                    }
                    .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

@MainActor
@Observable
private final class ClassificationDataViewModel {
    let repository: any MileageRepository
    private(set) var places: [FrequentPlace] = []
    private(set) var rules: [ClassificationRule] = []
    private(set) var trips: [Trip] = []

    init(repository: any MileageRepository) {
        self.repository = repository
    }

    func load() async {
        async let fetchedPlaces = repository.fetchFrequentPlaces()
        async let fetchedRules = repository.fetchClassificationRules()
        async let fetchedTrips = repository.fetchTrips()
        places = (try? await fetchedPlaces) ?? []
        rules = (try? await fetchedRules) ?? []
        trips = (try? await fetchedTrips) ?? []
    }

    func save(place: FrequentPlace) async {
        try? await repository.saveFrequentPlace(place)
        await load()
        NotificationCenter.default.post(name: .mileageClassificationDataDidChange, object: place.id)
    }

    func delete(place: FrequentPlace) async {
        for ruleID in SmartClassificationService.dependentRuleIDs(
            for: place.id,
            rules: rules
        ) {
            try? await repository.deleteClassificationRule(id: ruleID)
        }
        try? await repository.deleteFrequentPlace(id: place.id)
        await load()
        NotificationCenter.default.post(name: .mileageClassificationDataDidChange, object: place.id)
    }

    func save(rule: ClassificationRule) async {
        try? await repository.saveClassificationRule(rule)
        await load()
        NotificationCenter.default.post(name: .mileageClassificationDataDidChange, object: rule.id)
    }

    func delete(rule: ClassificationRule) async {
        try? await repository.deleteClassificationRule(id: rule.id)
        await load()
        NotificationCenter.default.post(name: .mileageClassificationDataDidChange, object: rule.id)
    }
}

enum ClassificationRulesAddAction: Equatable {
    case frequentPlace
    case classificationRule

    init(placeCount: Int) {
        self = placeCount >= 2 ? .classificationRule : .frequentPlace
    }
}

private struct EmptyStatePrimaryButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body.weight(.semibold))
            .frame(minHeight: 44)
            .padding(.horizontal, AppTheme.Spacing.medium)
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.Color.brand)
    }
}

private extension View {
    func emptyStatePrimaryButton() -> some View {
        modifier(EmptyStatePrimaryButton())
    }
}

struct FrequentPlacesManagementView: View {
    @State private var viewModel: ClassificationDataViewModel
    @State private var editingPlace: FrequentPlace?
    @State private var showingAdd = false

    init(repository: any MileageRepository) {
        _viewModel = State(initialValue: ClassificationDataViewModel(repository: repository))
    }

    var body: some View {
        List {
            if viewModel.places.isEmpty {
                ContentUnavailableView {
                    Label("No Frequent Places Yet", systemImage: "mappin.slash")
                } description: {
                    Text("Save meaningful locations such as Home, Office, or Client so they can be used in Classification Rules.")
                } actions: {
                    Button("Add Frequent Place") { showingAdd = true }
                        .emptyStatePrimaryButton()
                }
            } else {
                ForEach(viewModel.places) { place in
                    Button {
                        editingPlace = place
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.label)
                                .font(.headline)
                            if let address = place.address, !address.isEmpty {
                                Text(address)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Color.textSecondary)
                                    .lineLimit(2)
                            }
                            Text("Nearby radius: \(Int(place.radiusMeters)) meters")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task { await viewModel.delete(place: place) }
                        }
                    }
                }
            }
        }
        .settingsDetailScrollBehavior()
        .scrollIndicators(.hidden)
        .navigationTitle("Frequent Places")
        .toolbar {
            Button {
                showingAdd = true
            } label: {
                Label("Add Frequent Place", systemImage: "plus")
            }
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $showingAdd) {
            PlaceEditorView(
                place: nil,
                suggestedCoordinate: suggestedCoordinate
            ) { place in
                Task { await viewModel.save(place: place) }
            }
        }
        .sheet(item: $editingPlace) { place in
            PlaceEditorView(place: place, suggestedCoordinate: nil) { editedPlace in
                Task { await viewModel.save(place: editedPlace) }
            }
        }
    }

    private var suggestedCoordinate: TripCoordinate? {
        viewModel.trips.first?.endCoordinate ?? viewModel.trips.first?.startCoordinate
    }
}

private struct PlaceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let original: FrequentPlace?
    let onSave: (FrequentPlace) -> Void
    private let locationProvider: any PlaceLocationProviding
    @State private var label: String
    @State private var searchQuery = ""
    @State private var searchResults: [PlaceLocationSelection] = []
    @State private var selectedLocation: PlaceLocationSelection?
    @State private var radius: Double
    @State private var isLocating = false
    @State private var errorMessage: String?
    @State private var locationPermissionDenied = false

    init(
        place: FrequentPlace?,
        suggestedCoordinate: TripCoordinate?,
        locationProvider: any PlaceLocationProviding = ApplePlaceLocationService(),
        onSave: @escaping (FrequentPlace) -> Void
    ) {
        original = place
        self.locationProvider = locationProvider
        self.onSave = onSave
        _label = State(initialValue: place?.label ?? "")
        if let place, let address = place.address {
            _selectedLocation = State(
                initialValue: PlaceLocationSelection(
                    name: place.label,
                    address: address,
                    latitude: place.latitude,
                    longitude: place.longitude
                )
            )
        } else {
            _selectedLocation = State(initialValue: nil)
        }
        _radius = State(initialValue: place?.radiusMeters ?? 150)
        _initialCoordinate = State(
            initialValue: place.map { ($0.latitude, $0.longitude) }
                ?? suggestedCoordinate.map { ($0.latitude, $0.longitude) }
        )
    }

    @State private var initialCoordinate: (Double, Double)?

    var body: some View {
        NavigationStack {
            Form {
                Section("Place Name") {
                    TextField("Home, Office, or Client", text: $label)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                }

                Section("Location") {
                    if let selectedLocation {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(selectedLocation.name)
                                    .font(.headline)
                                Text(selectedLocation.address)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Color.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(AppTheme.Color.brand)
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        Text("Search for an address or use your current location.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Color.textSecondary)
                    }

                    TextField("Search address or place", text: $searchQuery)
                        .textContentType(.fullStreetAddress)
                        .submitLabel(.search)
                        .onSubmit { search() }

                    Button {
                        search()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                            .frame(minHeight: 44)
                    }
                    .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLocating)

                    Button {
                        useCurrentLocation()
                    } label: {
                        Label("Use Current Location", systemImage: "location.fill")
                            .frame(minHeight: 44)
                    }
                    .disabled(isLocating)

                    if isLocating {
                        HStack {
                            ProgressView()
                            Text("Finding location...")
                                .foregroundStyle(AppTheme.Color.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    ForEach(searchResults) { result in
                        Button {
                            selectedLocation = result
                            searchResults = []
                            searchQuery = ""
                            errorMessage = nil
                            locationPermissionDenied = false
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.name)
                                    .font(.headline)
                                Text(result.address)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Color.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Location error: \(errorMessage)")
                        if locationPermissionDenied {
                            Button("Open iPhone Settings") {
                                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                openURL(url)
                            }
                        }
                    }
                }

                Section("Nearby Radius") {
                    Stepper(
                        "Within \(Int(radius)) meters",
                        value: $radius,
                        in: 50...500,
                        step: 25
                    )
                    Text("Trips starting or ending within this distance can match the place.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("You choose the Place Name. MileMate stores the selected coordinates locally for matching and never labels a location as Home or Work on its own.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsDetailScrollBehavior()
            .scrollIndicators(.hidden)
            .navigationTitle(original == nil ? "Add Frequent Place" : "Edit Frequent Place")
            .navigationBarTitleDisplayMode(.inline)
            .task { await resolveInitialCoordinateIfNeeded() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let selectedLocation else { return }
                        onSave(
                            FrequentPlace(
                                id: original?.id ?? UUID(),
                                label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                                latitude: selectedLocation.latitude,
                                longitude: selectedLocation.longitude,
                                address: selectedLocation.address,
                                radiusMeters: radius,
                                createdAt: original?.createdAt ?? .now,
                                updatedAt: .now
                            )
                        )
                        dismiss()
                    }
                    .disabled(
                        label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        selectedLocation == nil ||
                        isLocating
                    )
                }
            }
        }
    }

    private func search() {
        let query = searchQuery
        isLocating = true
        errorMessage = nil
        locationPermissionDenied = false
        Task {
            do {
                searchResults = try await locationProvider.search(query: query)
            } catch {
                searchResults = []
                errorMessage = error.localizedDescription
                locationPermissionDenied = (error as? PlaceLocationError) == .permissionDenied
            }
            isLocating = false
        }
    }

    private func useCurrentLocation() {
        isLocating = true
        errorMessage = nil
        locationPermissionDenied = false
        Task {
            do {
                selectedLocation = try await locationProvider.currentLocation()
                searchResults = []
            } catch {
                errorMessage = error.localizedDescription
                locationPermissionDenied = (error as? PlaceLocationError) == .permissionDenied
            }
            isLocating = false
        }
    }

    private func resolveInitialCoordinateIfNeeded() async {
        guard selectedLocation == nil, let initialCoordinate else { return }
        isLocating = true
        defer { isLocating = false }
        do {
            selectedLocation = try await locationProvider.selection(
                latitude: initialCoordinate.0,
                longitude: initialCoordinate.1
            )
            self.initialCoordinate = nil
        } catch {
            errorMessage = error.localizedDescription
            locationPermissionDenied = (error as? PlaceLocationError) == .permissionDenied
        }
    }
}

struct ClassificationRulesView: View {
    @State private var viewModel: ClassificationDataViewModel
    @State private var showingAdd = false
    @State private var showingAddPlace = false
    @State private var continueToRuleAfterPlace = false

    init(repository: any MileageRepository) {
        _viewModel = State(initialValue: ClassificationDataViewModel(repository: repository))
    }

    var body: some View {
        List {
            if viewModel.rules.isEmpty {
                ContentUnavailableView {
                    Label("No Classification Rules Yet", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Create rules to automatically classify trips based on where they start or end.")
                } actions: {
                    if viewModel.places.count >= 2 {
                        Button("Add Rule") { showingAdd = true }
                            .emptyStatePrimaryButton()
                    } else {
                        Button("Add Frequent Place") {
                            showingAddPlace = true
                        }
                        .emptyStatePrimaryButton()
                    }
                }
            } else {
                ForEach(viewModel.rules) { rule in
                    Toggle(
                        isOn: Binding(
                            get: { rule.isEnabled },
                            set: { enabled in
                                var updated = rule
                                updated.isEnabled = enabled
                                updated.updatedAt = .now
                                Task { await viewModel.save(rule: updated) }
                            }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: AppTheme.Spacing.small) {
                                Text(rule.startLabel)
                                Image(systemName: "arrow.right")
                                    .accessibilityHidden(true)
                                Text(rule.endLabel)
                            }
                            .font(.headline)
                            Text(rule.classification.rawValue)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Color.textSecondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task { await viewModel.delete(rule: rule) }
                        }
                    }
                }
            }
        }
        .settingsDetailScrollBehavior()
        .scrollIndicators(.hidden)
        .navigationTitle("Classification Rules")
        .toolbar {
            Button {
                switch ClassificationRulesAddAction(placeCount: viewModel.places.count) {
                case .frequentPlace:
                    showingAddPlace = true
                case .classificationRule:
                    showingAdd = true
                }
            } label: {
                Label(
                    viewModel.places.count >= 2 ? "Add Rule" : "Add Frequent Place",
                    systemImage: "plus"
                )
            }
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $showingAddPlace, onDismiss: continueToRuleIfReady) {
            PlaceEditorView(place: nil, suggestedCoordinate: suggestedCoordinate) { place in
                Task {
                    await viewModel.save(place: place)
                    guard viewModel.places.count >= 2 else { return }
                    continueToRuleAfterPlace = true
                    if !showingAddPlace {
                        continueToRuleIfReady()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            RuleEditorView(places: viewModel.places) { rule in
                Task { await viewModel.save(rule: rule) }
            }
        }
    }

    private var suggestedCoordinate: TripCoordinate? {
        viewModel.trips.first?.endCoordinate ?? viewModel.trips.first?.startCoordinate
    }

    private func continueToRuleIfReady() {
        guard continueToRuleAfterPlace, viewModel.places.count >= 2 else { return }
        continueToRuleAfterPlace = false
        showingAdd = true
    }
}

private struct RuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let places: [FrequentPlace]
    let onSave: (ClassificationRule) -> Void
    @State private var startID: UUID?
    @State private var endID: UUID?
    @State private var classification = Trip.Classification.business

    var body: some View {
        NavigationStack {
            Form {
                Section("If This Trip Matches") {
                    Picker("From", selection: $startID) {
                        Text("Select a Frequent Place").tag(UUID?.none)
                        ForEach(places) { place in
                            Text(place.label).tag(Optional(place.id))
                        }
                    }
                    Picker("To", selection: $endID) {
                        Text("Select a Frequent Place").tag(UUID?.none)
                        ForEach(places) { place in
                            Text(place.label).tag(Optional(place.id))
                        }
                    }
                }

                Section("Then") {
                    Picker("Classify As", selection: $classification) {
                        Text("Business").tag(Trip.Classification.business)
                        Text("Personal").tag(Trip.Classification.personal)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("When a future trip matches both Frequent Places, MileMate applies the classification you choose. Trips without a matching enabled rule remain Unclassified for review.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsDetailScrollBehavior()
            .scrollIndicators(.hidden)
            .navigationTitle("Add Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let start = places.first(where: { place in
                            place.id == startID
                        }),
                        let end = places.first(where: { place in
                            place.id == endID
                        }) else {
                            return
                        }
                        onSave(
                            ClassificationRule(
                                startPlaceID: start.id,
                                startLabel: start.label,
                                endPlaceID: end.id,
                                endLabel: end.label,
                                classification: classification
                            )
                        )
                        dismiss()
                    }
                    .disabled(startID == nil || endID == nil || startID == endID)
                }
            }
        }
    }
}
