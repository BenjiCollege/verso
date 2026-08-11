import MapKit
import SwiftUI
import UIKit

struct PlaceBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion
    @Environment(GeofenceService.self) private var geofences

    @State private var isPicking = false

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<PlacePayload>) in
            VStack(alignment: .leading, spacing: Layout.Space.snug) {
                summary(payload)

                if payload.wrappedValue.target.isResolvable {
                    triggerRow(payload)
                    statusNotice
                }
            }
            .padding(.vertical, Layout.Space.tight)
            .sheet(isPresented: $isPicking) {
                PlacePickerSheet(payload: payload)
            }
            .onChange(of: payload.wrappedValue) { _, _ in
                Task { await geofences.refresh() }
            }
            .task {
                if geofences.availability == .notDetermined {
                    geofences.authority.requestAuthorization()
                }
                await geofences.refresh()
            }
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Rows

    private func summary(_ payload: Binding<PlacePayload>) -> some View {
        Button {
            isPicking = true
        } label: {
            HStack(spacing: Layout.Space.cosy) {
                Image(systemName: payload.wrappedValue.poiCategory == nil ? "mappin.circle" : "storefront")
                    .foregroundStyle(theme.accent)

                VStack(alignment: .leading, spacing: Layout.Space.hair) {
                    Text(displayName(payload.wrappedValue))
                        .versoText(.callout)
                        .foregroundStyle(payload.wrappedValue.target.isResolvable ? theme.ink : theme.inkTertiary)

                    if payload.wrappedValue.target.isResolvable {
                        Text("Within \(Int(payload.wrappedValue.radius)) m")
                            .versoText(.metadata)
                            .foregroundStyle(theme.inkSecondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .foregroundStyle(theme.inkTertiary)
            }
            .frame(minHeight: Layout.minimumHitTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Place"))
        .accessibilityValue(Text(displayName(payload.wrappedValue)))
        .accessibilityHint(Text("Double tap to choose a place"))
    }

    private func triggerRow(_ payload: Binding<PlacePayload>) -> some View {
        Picker("When", selection: payload.trigger) {
            ForEach(PlaceTrigger.allCases, id: \.self) { trigger in
                Text(trigger.displayName).tag(trigger)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(Text("Trigger"))
    }

    /// Section 7: when a place reminder is inactive, tell the user. Every
    /// reason it might not be running has a sentence here rather than silence.
    @ViewBuilder
    private var statusNotice: some View {
        let availability = geofences.availability
        let status = geofences.status(forBlock: block.id, noteID: block.note?.id ?? UUID())

        if let message = availability.message {
            notice(message, systemImage: "location.slash") {
                if availability == .notDetermined {
                    geofences.authority.requestAuthorization()
                } else if availability.offersSettingsLink {
                    openSettings()
                }
            }
        } else if let message = status.message {
            notice(message, systemImage: "exclamationmark.triangle", action: nil)
        } else {
            Label("Active", systemImage: "checkmark.circle")
                .versoText(.metadata)
                .foregroundStyle(theme.inkSecondary)
        }
    }

    @ViewBuilder
    private func notice(_ message: String, systemImage: String, action: (() -> Void)?) -> some View {
        let content = Label(message, systemImage: systemImage)
            .versoText(.footnote)
            .multilineTextAlignment(.leading)
            .foregroundStyle(action == nil ? theme.inkSecondary : theme.accent)
            .padding(Layout.Space.snug)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.inset, in: .rect(cornerRadius: Layout.Radius.tight))

        if let action {
            Button(action: action) { content.contentShape(.rect) }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func displayName(_ payload: PlacePayload) -> String {
        if !payload.name.isEmpty { return payload.name }
        if let category = payload.poiCategory {
            return PlaceResolver.displayName(for: MKPointOfInterestCategory(rawValue: category))
        }
        return String(localized: "Choose a place")
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
