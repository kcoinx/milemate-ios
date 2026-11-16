import Foundation
import SwiftUI
import UIKit

enum MileMateReleaseConfiguration {
    static let privacyPolicyURL = URL(string: "https://milemate-1df6d.web.app/privacy")
    static let termsOfUseURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )
    static let supportURL = URL(string: "https://milemate-1df6d.web.app/support")
    static let supportEmail: String? = "kcoinx@gmail.com"
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

struct FeedbackSubmissionConfiguration: Sendable {
    static let endpointBundleKey = "MileMateFeedbackEndpoint"
    let endpoint: URL

    static func fromBundle(_ bundle: Bundle = .main) -> FeedbackSubmissionConfiguration? {
        guard let value = bundle.object(forInfoDictionaryKey: endpointBundleKey) as? String,
              let endpoint = URL(string: value),
              endpoint.scheme == "https",
              endpoint.host != nil else {
            return nil
        }
        return FeedbackSubmissionConfiguration(endpoint: endpoint)
    }
}

enum FeedbackSubmissionError: LocalizedError, Equatable {
    case configurationRequired
    case messageTooShort
    case messageTooLong
    case invalidReplyEmail
    case rateLimited
    case rejected

    var errorDescription: String? {
        switch self {
        case .configurationRequired:
            "Feedback and support are not configured yet. Please try again in a future update."
        case .messageTooShort:
            "Please enter at least 10 characters."
        case .messageTooLong:
            "Your message must be 2,000 characters or fewer."
        case .invalidReplyEmail:
            "Enter a valid reply email address or leave it blank."
        case .rateLimited:
            "Too many messages were submitted. Please wait and try again later."
        case .rejected:
            "Your message could not be submitted. Please wait a moment and try again."
        }
    }
}

struct FeedbackSubmissionService: Sendable {
    static let maximumLength = 2_000
    private let configuration: FeedbackSubmissionConfiguration?
    private let session: URLSession

    init(
        configuration: FeedbackSubmissionConfiguration? = .fromBundle(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    static func validatedMessage(_ message: String) throws -> String {
        let value = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 10 else { throw FeedbackSubmissionError.messageTooShort }
        guard value.count <= maximumLength else { throw FeedbackSubmissionError.messageTooLong }
        return value
    }

    func submit(
        _ message: String,
        submissionType: SupportSubmissionType = .feedback,
        category: SupportSubmissionCategory = .generalFeedback,
        replyEmail: String? = nil,
        requestID: UUID = UUID()
    ) async throws {
        guard let configuration else {
            throw FeedbackSubmissionError.configurationRequired
        }
        let normalizedEmail = try Self.validatedReplyEmail(replyEmail)
        let payload = Payload(
            message: try Self.validatedMessage(message),
            submissionType: submissionType.rawValue,
            category: category.rawValue,
            replyEmail: normalizedEmail,
            requestID: requestID.uuidString,
            appVersion: AppBuildInformation.version(),
            build: AppBuildInformation.build(),
            platform: "iOS"
        )
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedbackSubmissionError.rejected
        }
        if httpResponse.statusCode == 429 {
            throw FeedbackSubmissionError.rateLimited
        }
        guard httpResponse.statusCode == 200,
              let result = try? JSONDecoder().decode(SubmissionResponse.self, from: data),
              result.stored else {
            throw FeedbackSubmissionError.rejected
        }
    }

    static func validatedReplyEmail(_ email: String?) throws -> String? {
        guard let email else { return nil }
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard value.count <= 254,
              parts.count == 2,
              !parts[0].isEmpty,
              parts[1].contains("."),
              !parts[1].hasPrefix("."),
              !parts[1].hasSuffix(".") else {
            throw FeedbackSubmissionError.invalidReplyEmail
        }
        return value
    }

    private struct Payload: Encodable {
        let message: String
        let submissionType: String
        let category: String
        let replyEmail: String?
        let requestID: String
        let appVersion: String
        let build: String
        let platform: String
    }

    private struct SubmissionResponse: Decodable {
        let stored: Bool
    }
}

enum SupportSubmissionType: String, Sendable {
    case feedback
    case support
}

enum SupportSubmissionCategory: String, CaseIterable, Identifiable, Sendable {
    case bugReport = "bug_report"
    case featureSuggestion = "feature_suggestion"
    case generalFeedback = "general_feedback"
    case question
    case helpRequest = "help_request"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bugReport: "Bug Report"
        case .featureSuggestion: "Feature Suggestion"
        case .generalFeedback: "General Feedback"
        case .question: "Question"
        case .helpRequest: "Help Request"
        }
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
                text: "The current local architecture stores trips, route coordinates, classifications, notes, vehicles, saved places, and auto-categorization rules on this device."
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
                NavigationLink("License & Important Information") {
                    LicenseInformationView()
                }
            }
        }
        .settingsDetailScrollBehavior()
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
            title: "Mileage and App Data",
            body: "MileMate stores mileage records on this iPhone, including trip times, distance, route coordinates, start and end descriptions, classifications, purposes, notes, vehicle information, Saved Places, auto-categorization rules, and app preferences. Signing in does not automatically upload or back up this mileage data to Firebase."
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
            title: "Accounts and Authentication",
            body: "You may use MileMate as a guest or sign in with Apple or Google. Apple or Google and Firebase Authentication process identifiers, authentication tokens, and any name or email address made available for sign-in. MileMate uses that identity to keep local account data separated on this device. Authentication credentials are stored securely for session restoration."
        ),
        LegalDocumentSection(
            title: "Feedback and Support",
            body: "If you submit feedback or contact support, MileMate sends the category, message, optional reply email address, request identifier, app version, build number, and platform to a Firebase Cloud Function. The submission is stored in Cloud Firestore so it can be reviewed. A one-way keyed value derived from the request's network address is stored temporarily for rate limiting; the raw network address is not stored in the feedback database. Do not include passwords, payment details, or sensitive trip information."
        ),
        LegalDocumentSection(
            title: "Apple Services and Sharing",
            body: "Map displays, route presentation, address lookup, and place search may be processed by Apple's MapKit and geocoding services under Apple's applicable terms and privacy practices. MileMate does not include third-party advertising trackers and does not sell mileage records."
        ),
        LegalDocumentSection(
            title: "Retention and Deletion",
            body: "Mileage records remain on this device until you delete individual records, use Delete All MileMate Data, delete the owning account, or remove the app and its data through iOS. Delete All MileMate Data stops active tracking, removes MileMate-owned local records and restoration state, resets MileMate preferences, and cancels MileMate local notifications. Account deletion removes the authentication account and only that account's locally owned data. Feedback and support submissions are assigned a 365-day retention period, after which they become eligible for Firestore TTL deletion. TTL removal may occur after the expiration date and is not immediate. Account deletion does not automatically delete feedback or support submissions; contact support to request earlier removal."
        ),
        LegalDocumentSection(
            title: "Your Permissions and Controls",
            body: "You can revoke Location, Motion & Fitness, or Notification permission in iPhone Settings. Revoking a permission may prevent automatic tracking or related alerts from working. System permission decisions are not reset by Delete All MileMate Data."
        ),
        LegalDocumentSection(
            title: "Contact",
            body: "Use Contact Support in MileMate, visit the public Support page, or email kcoinx@gmail.com for privacy questions, requests, or help with account deletion."
        )
    ]

    var body: some View {
        List {
            Section {
                Text("Effective November 16, 2026")
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
        .settingsDetailScrollBehavior()
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LicenseInformationView: View {
    private let sections = [
        LegalDocumentSection(
            title: "Mileage and Tax Information",
            body: "MileMate is a mileage-recording and reporting tool. You are responsible for reviewing recorded trips and classifications. Mileage deductions and Estimated Tax Savings are informational estimates, not tax, accounting, or legal advice, and do not guarantee eligibility or acceptance by a tax authority."
        ),
        LegalDocumentSection(
            title: "Tracking Accuracy",
            body: "GPS, motion recognition, permissions, background execution, environmental conditions, and iOS behavior can delay, interrupt, or miss mileage recording. Review records promptly and retain any documentation required for tax or business purposes."
        ),
        LegalDocumentSection(
            title: "Purchases",
            body: "Eligible users can complete up to 10 free trips before new trip recording is restricted. MileMate Pro Monthly is an auto-renewable subscription and MileMate Pro Lifetime is a non-consumable purchase. Prices and availability are provided by the App Store. A subscription renews unless canceled through Apple at least 24 hours before the end of the current period. Cancellation leaves access active through the paid period. Deleting MileMate or deleting an account does not cancel an App Store subscription; manage or cancel it in Apple's subscription settings."
        ),
        LegalDocumentSection(
            title: "Support",
            body: "For help, use Contact Support in MileMate, visit the public Support page, or email kcoinx@gmail.com. Do not include passwords, payment details, or sensitive trip information."
        )
    ]

    var body: some View {
        List {
            Section {
                Text("MileMate is licensed under Apple's Standard End User License Agreement.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let url = MileMateReleaseConfiguration.termsOfUseURL {
                    Link("Open Apple's Standard EULA", destination: url)
                }
                if let url = MileMateReleaseConfiguration.supportURL {
                    Link("Open MileMate Support", destination: url)
                }
            }
            ForEach(sections) { section in
                Section(section.title) {
                    Text(section.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .settingsDetailScrollBehavior()
        .navigationTitle("License & Important Information")
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
        Topic(title: "Saved Places & Auto-Categorize Trips", detail: "Saved Places are locations you name. Rules you approve can categorize matching routes; automatic categorization only applies enabled rules."),
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
                NavigationLink("Contact Support") {
                    ContactSupportView()
                }
                if let url = MileMateReleaseConfiguration.supportURL {
                    Link("Open Support Website", destination: url)
                }
                if let email = MileMateReleaseConfiguration.supportEmail,
                   let url = URL(string: "mailto:\(email)") {
                    Link("Email Support", destination: url)
                }
                Text("Use Contact Support for questions or help requests. Do not include passwords, payment details, or sensitive trip information.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsDetailScrollBehavior()
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SendFeedbackView: View {
    var body: some View {
        SupportSubmissionForm(submissionType: .feedback)
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct ContactSupportView: View {
    var body: some View {
        SupportSubmissionForm(submissionType: .support)
            .navigationTitle("Contact Support")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SupportSubmissionForm: View {
    private enum FocusedField: Hashable {
        case replyEmail
        case message
    }

    private enum SubmissionState: Equatable {
        case idle
        case submitting
        case success
        case failure(String)
    }

    @State private var feedback = ""
    @State private var replyEmail = ""
    @State private var requestID = UUID()
    @State private var category: SupportSubmissionCategory
    @State private var submissionState = SubmissionState.idle
    @State private var showingSuccessConfirmation = false
    @FocusState private var focusedField: FocusedField?
    @Environment(\.dismiss) private var dismiss
    private let service = FeedbackSubmissionService()
    private let submissionType: SupportSubmissionType

    init(submissionType: SupportSubmissionType) {
        self.submissionType = submissionType
        _category = State(
            initialValue: submissionType == .feedback ? .generalFeedback : .question
        )
    }

    private var availableCategories: [SupportSubmissionCategory] {
        switch submissionType {
        case .feedback:
            [.bugReport, .featureSuggestion, .generalFeedback]
        case .support:
            [.question, .helpRequest]
        }
    }

    var body: some View {
        List {
            Section(submissionType == .feedback ? "Your Feedback" : "Your Question") {
                Text(
                    submissionType == .feedback
                        ? "Tell us what worked well or what could be improved."
                        : "Tell us what you need help with."
                )
                    .foregroundStyle(.secondary)
                Picker("Category", selection: $category) {
                    ForEach(availableCategories) { item in
                        Text(item.title).tag(item)
                    }
                }
                if submissionType == .support {
                    TextField("Reply email (optional)", text: $replyEmail)
                        .focused($focusedField, equals: .replyEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityHint("Used only if you want MileMate support to reply")
                }
                TextEditor(text: $feedback)
                    .focused($focusedField, equals: .message)
                    .frame(minHeight: 150)
                    .accessibilityLabel("Feedback message")
                    .onChange(of: feedback) { _, value in
                        if value.count > FeedbackSubmissionService.maximumLength {
                            feedback = String(value.prefix(FeedbackSubmissionService.maximumLength))
                        }
                        if submissionState != .submitting {
                            submissionState = .idle
                        }
                    }
                Text("\(feedback.count) / \(FeedbackSubmissionService.maximumLength)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Button {
                    submitFeedback()
                } label: {
                    Group {
                        if submissionState == .submitting {
                            ProgressView()
                        } else {
                            Text(submissionType == .feedback ? "Submit Feedback" : "Contact Support")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
                .disabled(submissionState == .submitting || feedback.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)

                switch submissionState {
                case .success:
                    Label(
                        submissionType == .feedback
                            ? "Thank you. Your feedback was saved securely."
                            : "Your support request was saved securely.",
                        systemImage: "checkmark.circle.fill"
                    )
                        .foregroundStyle(AppTheme.Color.positive)
                case .failure(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                case .idle, .submitting:
                    EmptyView()
                }
            }
            Section("Privacy") {
                Text("MileMate stores only the message you type, your selected category, an optional reply email, and basic app metadata. Trip coordinates, routes, notes, mileage records, and account details are not included.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsDetailScrollBehavior()
        .alert(
            submissionType == .feedback ? "Feedback Sent" : "Support Request Sent",
            isPresented: $showingSuccessConfirmation
        ) {
            Button("Done") { dismiss() }
        } message: {
            Text(
                submissionType == .feedback
                    ? "Thank you. Your feedback was submitted successfully."
                    : "Your support request was submitted successfully."
            )
        }
    }

    private func submitFeedback() {
        guard submissionState != .submitting else { return }
        submissionState = .submitting
        Task {
            do {
                try await service.submit(
                    feedback,
                    submissionType: submissionType,
                    category: category,
                    replyEmail: submissionType == .support ? replyEmail : nil,
                    requestID: requestID
                )
                feedback = ""
                replyEmail = ""
                requestID = UUID()
                submissionState = .success
                focusedField = nil
                showingSuccessConfirmation = true
            } catch {
                submissionState = .failure(
                    (error as? LocalizedError)?.errorDescription ??
                        "Your message could not be submitted. Please try again."
                )
            }
        }
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
                NavigationLink("License & Important Information") {
                    LicenseInformationView()
                }
            }
        }
        .settingsDetailScrollBehavior()
        .navigationTitle("About MileMate")
        .navigationBarTitleDisplayMode(.inline)
    }
}
