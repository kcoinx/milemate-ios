import SwiftUI
import UIKit

enum MileMateReleaseConfiguration {
    // Supply hosted HTTPS destinations and a real support contact before App Store submission.
    static let privacyPolicyURL: URL? = nil
    static let termsOfUseURL: URL? = nil
    static let supportEmail: String? = nil
    static let legalEntityName: String? = nil
}

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
                NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                NavigationLink("Terms of Use") { TermsOfUseView() }
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

private struct LegalDocumentSection: Identifiable {
    let title: String
    let body: String
    var id: String { title }
}

struct PrivacyPolicyView: View {
    private let sections = [
        LegalDocumentSection(
            title: "Data MileMate Stores",
            body: "MileMate stores mileage records on this iPhone, including trip times, distance, route coordinates, start and end descriptions, classification, purpose, notes, vehicle information, Frequent Places, Classification Rules, and app preferences."
        ),
        LegalDocumentSection(
            title: "Location and Route Data",
            body: "Location is used to detect eligible driving, calculate distance, and create route records. Always Location supports automatic tracking in the background. Precise location is requested while detecting or recording a trip."
        ),
        LegalDocumentSection(
            title: "Motion & Fitness",
            body: "Motion activity is used to distinguish automotive movement from walking, running, cycling, and stationary activity. MileMate does not use Motion & Fitness data to infer a trip's Business or Personal classification."
        ),
        LegalDocumentSection(
            title: "Notifications",
            body: "If authorized, MileMate uses local notifications for completed automatic trips, trips awaiting review, and the long-running manual-trip safeguard. Notification preferences can be changed in MileMate and system authorization can be changed in iPhone Settings."
        ),
        LegalDocumentSection(
            title: "Storage and Sharing",
            body: "The current MileMate architecture stores its mileage database locally on this device. The app does not currently include accounts, cloud synchronization, advertising, or analytics services. Map and place-search requests may be processed by Apple's MapKit and geocoding services under Apple's applicable terms and privacy practices. MileMate does not send the local mileage database to the product owner or advertising companies."
        ),
        LegalDocumentSection(
            title: "Retention and Deletion",
            body: "Records remain on this device until you delete individual records, use Delete All MileMate Data, or remove the app and its data through iOS. Delete All MileMate Data stops active tracking, removes MileMate-owned local records and restoration state, resets MileMate preferences, and cancels MileMate local notifications."
        ),
        LegalDocumentSection(
            title: "Your Permissions and Controls",
            body: "You can revoke Location, Motion & Fitness, or Notification permission in iPhone Settings. Revoking a permission may prevent automatic tracking or related alerts from working. System permission decisions are not reset by Delete All MileMate Data."
        ),
        LegalDocumentSection(
            title: "Contact",
            body: "A public support contact has not yet been configured in this build. Until one is supplied, the in-app Send Feedback action can create a non-sensitive message for an app you choose."
        )
    ]

    var body: some View {
        List {
            Section {
                Text("Effective for the current local-only version of MileMate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let url = MileMateReleaseConfiguration.privacyPolicyURL {
                    Link("Open Hosted Privacy Policy", destination: url)
                }
            }
            ForEach(sections) { section in
                Section(section.title) {
                    Text(section.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsOfUseView: View {
    private let sections = [
        LegalDocumentSection(
            title: "Purpose of MileMate",
            body: "MileMate is a mileage-recording and reporting tool. You are responsible for reviewing recorded trips and deciding whether each trip is Business, Personal, or Unclassified."
        ),
        LegalDocumentSection(
            title: "Estimates and Tax Information",
            body: "Mileage deductions and Estimated Tax Savings are informational estimates based on the app's configured rates and your classifications. They are not tax, accounting, or legal advice and do not guarantee eligibility, savings, or acceptance by a tax authority."
        ),
        LegalDocumentSection(
            title: "Record Accuracy",
            body: "GPS, motion recognition, background execution, device settings, environmental conditions, and operating-system behavior can delay, interrupt, or miss mileage recording. MileMate does not guarantee that every trip, route, distance, address, or classification will be complete or exact."
        ),
        LegalDocumentSection(
            title: "Your Responsibilities",
            body: "You are responsible for maintaining required device permissions, keeping the app available for background operation, reviewing records promptly, correcting classifications and trip details, and retaining any documentation required for tax or business purposes."
        ),
        LegalDocumentSection(
            title: "Automatic Classification",
            body: "Automatic Classification applies only rules you enable. A matching rule uses the Business or Personal classification you selected. Trips without a matching enabled rule remain Unclassified for review."
        ),
        LegalDocumentSection(
            title: "Local Data",
            body: "The current version has no MileMate account or cloud synchronization. Deleting app data or removing the app may permanently remove records that have not been exported or otherwise retained by you."
        ),
        LegalDocumentSection(
            title: "Product Changes and Availability",
            body: "Features may change as MileMate evolves. Availability can also depend on compatible Apple hardware, iOS capabilities, permissions, and services."
        ),
        LegalDocumentSection(
            title: "Provider and Contact",
            body: "The product owner's formal legal entity name, governing terms, and public support contact have not yet been configured. Those release details must be supplied before these terms are used as the final public legal agreement."
        )
    ]

    var body: some View {
        List {
            Section {
                Text("Terms for the current local-only MileMate product.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let url = MileMateReleaseConfiguration.termsOfUseURL {
                    Link("Open Hosted Terms of Use", destination: url)
                }
            }
            ForEach(sections) { section in
                Section(section.title) {
                    Text(section.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("Terms of Use")
        .navigationBarTitleDisplayMode(.inline)
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
                NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                NavigationLink("Terms of Use") { TermsOfUseView() }
            }
        }
        .navigationTitle("About MileMate")
        .navigationBarTitleDisplayMode(.inline)
    }
}
