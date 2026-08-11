import MapKit
import SwiftUI

/// Choosing a place — either a point on the map, or a whole category.
///
/// The category option is the one that matters: "any grocery store" is what
/// makes a shopping list useful in a town you have never shopped in.
struct PlacePickerSheet: View {
    @Binding var payload: PlacePayload

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(GeofenceService.self) private var geofences

    private enum Mode: String, CaseIterable {
        case category
        case point

        var displayName: LocalizedStringResource {
            switch self {
            case .category: "A kind of place"
            case .point: "A specific place"
            }
        }
    }

    @State private var mode: Mode
    @State private var camera: MapCameraPosition = .automatic
    @State private var pin: Coordinate?
    @State private var radius: Double

    init(payload: Binding<PlacePayload>) {
        _payload = payload
        _mode = State(initialValue: payload.wrappedValue.coordinate == nil ? .category : .point)
        _pin = State(initialValue: payload.wrappedValue.coordinate)
        _radius = State(initialValue: payload.wrappedValue.radius)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(Layout.Space.regular)

                switch mode {
                case .category: categoryList
                case .point: pointPicker
                }
            }
            .navigationTitle("Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commit() }
                        .disabled(mode == .point && pin == nil)
                }
            }
        }
    }

    // MARK: - Category

    private var categoryList: some View {
        List {
            Section {
                ForEach(PlaceResolver.offeredCategories, id: \.rawValue) { category in
                    Button {
                        payload.poiCategory = category.rawValue
                        payload.coordinate = nil
                        payload.name = PlaceResolver.displayName(for: category)
                    } label: {
                        HStack {
                            Text(PlaceResolver.displayName(for: category))
                                .versoText(.chromeBody)
                                .foregroundStyle(theme.ink)
                            Spacer(minLength: 0)
                            if payload.poiCategory == category.rawValue {
                                Image(systemName: "checkmark").foregroundStyle(theme.accent)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(payload.poiCategory == category.rawValue ? [.isSelected] : [])
                }
            } footer: {
                Text("Verso finds the nearest few matches wherever you are, and updates them as you move.")
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Point

    private var pointPicker: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $camera) {
                    if let pin {
                        Marker(payload.name.isEmpty ? String(localized: "Here") : payload.name, coordinate: pin.clCoordinate)
                            .tint(theme.accent)
                        MapCircle(center: pin.clCoordinate, radius: radius)
                            .foregroundStyle(theme.accent.opacity(0.15))
                            .stroke(theme.accent, lineWidth: Layout.hairline * 2)
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                }
                .onTapGesture(coordinateSpace: .local) { position in
                    guard let coordinate = proxy.convert(position, from: .local) else { return }
                    pin = Coordinate(coordinate)
                }
                .accessibilityLabel(Text("Map"))
                .accessibilityHint(Text("Double tap the map to place a pin"))
            }

            VStack(alignment: .leading, spacing: Layout.Space.snug) {
                TextField(
                    "Name",
                    text: $payload.name,
                    prompt: Text("Name this place").foregroundStyle(theme.inkTertiary)
                )
                .textFieldStyle(.plain)
                .versoText(.chromeBody)

                HStack {
                    Text("Within \(Int(radius)) m")
                        .versoText(.metadata)
                        .foregroundStyle(theme.inkSecondary)
                    Slider(value: $radius, in: 100...2_000, step: 50)
                        .accessibilityLabel(Text("Radius in metres"))
                        .accessibilityValue(Text("\(Int(radius)) metres"))
                }
            }
            .padding(Layout.Space.regular)
        }
        .task {
            if pin == nil, let location = geofences.authority.userLocation {
                camera = .region(
                    MKCoordinateRegion(
                        center: location.clCoordinate,
                        latitudinalMeters: 2_000,
                        longitudinalMeters: 2_000
                    )
                )
            }
        }
    }

    // MARK: - Commit

    private func commit() {
        switch mode {
        case .category:
            payload.coordinate = nil
        case .point:
            payload.coordinate = pin
            payload.poiCategory = nil
            payload.radius = PlaceTarget.clampRadius(radius)
        }
        dismiss()
    }
}
