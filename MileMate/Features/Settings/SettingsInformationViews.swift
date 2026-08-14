import SwiftUI
import UIKit

enum AppBuildInformation {
    static func version(
        from dictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> String {
        dictionary?["CFBundleShortVersionString"] as? String ?? "Unavailable"
    }

    static func build(
        from dictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> String {
        dictionary?["CFBundleVersion"] as? String ?? "Unavailable"
    }

    static var displayValue: String {
        "Version \(version()) (\(build()))"
    }
}

@MainActor
enum FeedbackContent {
    static func message(
        version: String = AppBuildInformation.version(),
        build: String = AppBuildInformation.build(),
        systemVersion: String = UIDevice.current.systemVersion
    ) -> String {
        """
        MileMate Feedback

        Tell us what worked well or what could be improved:


        App version: \(version) (\(build))
        iOS version: \(systemVersion)
        """
    }
}

struct PrivacyInformationView: View {
    var body: some View {
        List {
            informationSection(
                "Location",
                icon: "location.fill",
                text: "MileMate uses location to measure mileage and build a route while a trip is being recorded. Always Location allows automatic mileage tracking to continue in the background. Precise location is used during active recording."
            )
            informationSection(
                "Motion & Fitness",
                icon: "figure.walk.motion",
                text: "Motion activity helps distinguish driving from walking, running, cycling, and stationary movement so automatic tracking can operate more accurately and efficiently."
            )
            informationSection(
                "Data Stored on This iPhone",
                icon: "iphone",
                text: "The current local architecture stores trips, route coordinates, classifications, notes, vehicles, frequent places, and classification rules on this device."
            )
            informationSection(
                "Notifications",
                icon: "bell.fill",
                text: "Notifications can confirm completed automatic trips, remind you about trips awaiting classification, and provide the long-running manual-trip safeguard."
            )
            informationSection(
                "Your Controls",
                icon: "slider.horizontal.3",
                text: "You can change MileMate preferences in Settings, manage iOS permissions in iPhone Settings, or permanently remove MileMate-owned local data with Delete All MileMate Data."
            )
            Section("External Policies") {
                LabeledContent("Privacy Policy", value: "Not yet provided")
                LabeledContent("Terms", value: "Not yet provided")
                Text("Public Privacy Policy and Terms URLs must be supplied before App Store submission.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func informationSection(_ title: String, icon: String, text: String) -> some View {
        Section {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } header: {
            Label(title, systemImage: icon)
        }
    }
}

struct HelpSupportView: View {
    private struct Topic: Identifiable {
        let title: String
        let detail: String
        var id: String { title }
    }

    private let topics: [Topic] = [
        Topic(title: "How Automatic Tracking Works", detail: "With Automatic Tracking enabled and required permissions granted, MileMate uses motion and battery-aware location services to recognize driving, record qualifying trips, and save trips that need classification."),
        Topic(title: "How Manual Tracking Works", detail: "Turn off Automatic Tracking, then use Start Trip on Dashboard. Stop the trip when finished and review it before saving."),
        Topic(title: "Location & Motion Permissions", detail: "Automatic tracking needs Always Location and Motion & Fitness. If a status is insufficient, tap its permission row in Settings to open iPhone Settings."),
        Topic(title: "Reviewing and Classifying Trips", detail: "Open Trips, then Trips to Review. Classify each trip as Business or Personal and add a purpose, vehicle, or notes when useful."),
        Topic(title: "Frequent Places & Classification Rules", detail: "Frequent Places are locations you name. Approved rules use those places to classify matching routes; Automatic Classification only applies enabled rules."),
        Topic(title: "Notifications", detail: "Completion alerts confirm qualifying automatic trips. Review reminders combine outstanding trips into a next-day reminder. Each notification type can be controlled separately."),
        Topic(title: "Reports & Exports", detail: "Reports use qualifying Business trips. Select a period and vehicle, then preview or share PDF, CSV, or IRS mileage reports."),
        Topic(title: "Battery Usage", detail: "MileMate uses low-power monitoring while idle and requests precise background location only when detecting or recording a drive."),
        Topic(title: "Troubleshooting Automatic Tracking", detail: "Confirm Automatic Tracking is enabled, Location says Always Allowed, Motion & Fitness says Allowed, and Background App Refresh and Location Services remain available in iPhone Settings.")
    ]

    var body: some View {
        List {
            Section {
                ForEach(topics) { topic in
                    DisclosureGroup(topic.title) {
                        Text(topic.detail)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }
            }
            Section("Contact") {
                Text("A public support email or support URL has not yet been configured. Use Send Feedback to share a non-sensitive feedback template through an app of your choice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SendFeedbackView: View {
    private var feedback: String { FeedbackContent.message() }

    var body: some View {
        List {
            Section {
                Text("Share feedback using Mail, Messages, Notes, or another app. The template includes only app/build and iOS version information.")
                ShareLink(item: feedback, subject: Text("MileMate Feedback")) {
                    Label("Share Feedback", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
            Section("Privacy") {
                Text("Trip coordinates, addresses, routes, notes, and mileage records are never inserted into the feedback template automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Support Destination") {
                Text("No official MileMate support email or feedback URL is currently configured. The product owner must provide one before App Store submission.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Send Feedback")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutMileMateView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: AppTheme.Spacing.medium) {
                    Image("LaunchBrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 104, height: 104)
                        .accessibilityHidden(true)
                    Text("MileMate")
                        .font(.title2.bold())
                    Text("Automatic mileage clarity for people who drive for work.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(AppBuildInformation.displayValue)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.large)
                .accessibilityElement(children: .combine)
            }
            Section("Resources") {
                NavigationLink("Privacy") { PrivacyInformationView() }
                NavigationLink("Help & Support") { HelpSupportView() }
                LabeledContent("Privacy Policy", value: "Not yet provided")
                LabeledContent("Terms", value: "Not yet provided")
            }
        }
        .navigationTitle("About MileMate")
        .navigationBarTitleDisplayMode(.inline)
    }
}
