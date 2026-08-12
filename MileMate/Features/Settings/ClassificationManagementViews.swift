import Observation
import SwiftUI

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
                ContentUnavailableView(
                    "No Frequent Places",
                    systemImage: "mappin.slash",
                    description: Text("Add and confirm labels such as Home, Work, Client Office, Warehouse, or Job Site.")
                )
            } else {
                ForEach(viewModel.places) { place in
                    Button {
                        editingPlace = place
                    } label: {
                        LabeledContent(place.label, value: "\(Int(place.radiusMeters)) m radius")
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
        .scrollIndicators(.hidden)
        .navigationTitle("Frequent Places")
        .toolbar {
            Button {
                showingAdd = true
            } label: {
                Label("Add Place", systemImage: "plus")
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
    let original: FrequentPlace?
    let onSave: (FrequentPlace) -> Void
    @State private var label: String
    @State private var latitude: String
    @State private var longitude: String
    @State private var radius: Double

    init(
        place: FrequentPlace?,
        suggestedCoordinate: TripCoordinate?,
        onSave: @escaping (FrequentPlace) -> Void
    ) {
        original = place
        self.onSave = onSave
        _label = State(initialValue: place?.label ?? "")
        _latitude = State(initialValue: String(place?.latitude ?? suggestedCoordinate?.latitude ?? 0))
        _longitude = State(initialValue: String(place?.longitude ?? suggestedCoordinate?.longitude ?? 0))
        _radius = State(initialValue: place?.radiusMeters ?? 150)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Place label", text: $label)
                LabeledContent("Latitude") {
                    TextField("Latitude", text: $latitude).keyboardType(.numbersAndPunctuation)
                }
                LabeledContent("Longitude") {
                    TextField("Longitude", text: $longitude).keyboardType(.numbersAndPunctuation)
                }
                Stepper("Nearby radius: \(Int(radius)) m", value: $radius, in: 50...500, step: 25)
                Text("Coordinates remain private on this device. MileMate never assigns Home or Work without your confirmation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(original == nil ? "Add Place" : "Edit Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let latitude = Double(latitude),
                              let longitude = Double(longitude) else { return }
                        onSave(
                            FrequentPlace(
                                id: original?.id ?? UUID(),
                                label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                                latitude: latitude,
                                longitude: longitude,
                                radiusMeters: radius,
                                createdAt: original?.createdAt ?? .now,
                                updatedAt: .now
                            )
                        )
                        dismiss()
                    }
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ClassificationRulesView: View {
    @State private var viewModel: ClassificationDataViewModel
    @State private var showingAdd = false

    init(repository: any MileageRepository) {
        _viewModel = State(initialValue: ClassificationDataViewModel(repository: repository))
    }

    var body: some View {
        List {
            if viewModel.rules.isEmpty {
                ContentUnavailableView(
                    "No Classification Rules",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Approved rules can classify confirmed recurring routes automatically.")
                )
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
                            Text("\(rule.startLabel) → \(rule.endLabel)")
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
        .scrollIndicators(.hidden)
        .navigationTitle("Classification Rules")
        .toolbar {
            if viewModel.places.count >= 2 {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            }
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $showingAdd) {
            RuleEditorView(places: viewModel.places) { rule in
                Task { await viewModel.save(rule: rule) }
            }
        }
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
                Picker("Start place", selection: $startID) {
                    Text("Select").tag(UUID?.none)
                    ForEach(places) { place in
                        Text(place.label).tag(Optional(place.id))
                    }
                }
                Picker("End place", selection: $endID) {
                    Text("Select").tag(UUID?.none)
                    ForEach(places) { place in
                        Text(place.label).tag(Optional(place.id))
                    }
                }
                Picker("Classification", selection: $classification) {
                    Text("Business").tag(Trip.Classification.business)
                    Text("Personal").tag(Trip.Classification.personal)
                }
                Text("This rule is created only after you confirm it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
