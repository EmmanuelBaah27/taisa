import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public enum TaisaBottomChromeContract {
    public static let fadeHeight = TaisaControlMetric.primaryNavigationReservedHeight
    public static let coversBottomSafeArea = true
}
/// Shared bottom chrome for primary destinations.
///
/// Place this component in a root `safeAreaInset(edge: .bottom)` so its fade
/// owns the home-indicator region and its height reserves scrolling content.
public struct TaisaBottomChrome<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: TaisaBottomChromeContract.fadeHeight, alignment: .bottom)
            .background {
                PageEdgeFade(.navigation)
                    .ignoresSafeArea(edges: [.horizontal, .bottom])
                    .allowsHitTesting(false)
            }
    }
}
/// Shared top chrome for the primary Home, Chats, and You destinations.
public struct TaisaPageHeader<Actions: View>: View {
    private let title: String
    private let actions: Actions

    public init(
        _ title: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.actions = actions()
    }

    public var body: some View {
        HStack(spacing: TaisaSpacing.standard.rawValue) {
            Text(title)
                .font(.system(.title, weight: .semibold))
                .foregroundStyle(TaisaColor.foreground.color)
                .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .frame(height: TaisaControlMetric.appBarHeight)
        .background {
            PageEdgeFade(.header)
                .ignoresSafeArea(edges: [.top, .horizontal])
        }
    }
}
public struct TaisaDatedPageHeader<Actions: View>: View {
    private let date: String
    private let title: String
    private let actions: Actions

    public init(date: String, title: String, @ViewBuilder actions: () -> Actions) {
        self.date = date
        self.title = title
        self.actions = actions()
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: TaisaSpacing.standard.rawValue) {
            VStack(alignment: .leading, spacing: TaisaTaskSpacing.headerGap) {
                TaisaText(role: .taskSupporting, color: .mutedForeground, content: date)
                TaisaText(role: .datedPageTitle, content: title)
            }
            Spacer(minLength: 0)
            actions
        }
        .padding(.horizontal, TaisaSpacing.content.rawValue)
        .padding(.vertical, TaisaSpacing.control.rawValue)
        .frame(height: TaisaControlMetric.taskHeaderHeight)
        .background(TaisaColor.background.color)
    }
}

public struct TaisaInlineTaskComposer: View {
    @FocusState private var titleIsFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @State private var showsDueDatePicker = false
    @State private var draftDueDate = Date()
    @Binding private var title: String
    @Binding private var dueDate: Date?
    private let submit: @MainActor () -> Void

    public init(title: Binding<String>, dueDate: Binding<Date?>, submit: @escaping @MainActor () -> Void) {
        _title = title
        _dueDate = dueDate
        self.submit = submit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TaisaSpacing.control.rawValue) {
            TextField("Add task…", text: $title, axis: .vertical)
                .font(TaisaTypography.taskTitle.font)
                .lineLimit(1...3)
                .focused($titleIsFocused)
                .accessibilityLabel("Task title")
            HStack {
                Button {
                    draftDueDate = dueDate ?? Date()
                    titleIsFocused = false
                    showsDueDatePicker = true
                } label: {
                    dueLabel(dueDate?.taskComposerLabel ?? "Due")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dueDate.map { "Due date, \($0.taskComposerLabel)" } ?? "Due")
                .accessibilityIdentifier("task.composer.due")
                Spacer(minLength: 0)
                Button(action: submit) {
                    CentralIcon(.arrowUp)
                        .frame(width: TaisaControlMetric.compactActionIcon, height: TaisaControlMetric.compactActionIcon)
                        .frame(width: TaisaControlMetric.taskControl, height: TaisaControlMetric.taskControl)
                        .background(TaisaColor.primaryAction.color, in: Circle())
                }
                    .buttonStyle(.plain)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("task.composer.submit")
                    .accessibilityLabel("Save task")
            }
        }
        .padding(TaisaSpacing.control.rawValue)
        .frame(height: TaisaControlMetric.taskComposerCardHeight)
        .background(TaisaColor.background.color)
        .clipShape(RoundedRectangle(cornerRadius: TaisaRadius.taskComposer))
        .overlay { RoundedRectangle(cornerRadius: TaisaRadius.taskComposer).stroke(TaisaColor.border.color.opacity(0.7)) }
        .shadow(
            color: TaisaColor.foreground.color.opacity(TaisaEffect.taskComposerShadowOpacity),
            radius: TaisaEffect.taskComposerShadowRadius
        )
        .padding(TaisaSpacing.control.rawValue)
        .frame(height: TaisaControlMetric.taskComposerHeight)
        .background { PageEdgeFade(.navigation) }
        // Home keeps its page geometry stable while the software keyboard is up.
        // Reserve the keyboard's real end-frame height here so the card remains
        // immediately above it and hardware-keyboard layouts keep their baseline.
        .padding(.bottom, keyboardHeight)
        .task { titleIsFocused = true }
#if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            keyboardHeight = keyboardEndFrame(from: notification).height
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
#endif
        .sheet(isPresented: $showsDueDatePicker) {
            NavigationStack {
                DatePicker("Due date", selection: $draftDueDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(TaisaSpacing.standard.rawValue)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("Due date").font(.headline)
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { closeDueDatePicker() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                dueDate = draftDueDate
                                closeDueDatePicker()
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func dueLabel(_ text: String) -> some View {
        HStack(spacing: TaisaTaskSpacing.dueGap) {
            CentralIcon(.calendar)
                .frame(width: TaisaControlMetric.taskDueIcon, height: TaisaControlMetric.taskDueIcon)
            TaisaText(role: .taskSupporting, color: .mutedForeground, content: text)
        }
    }

    private func closeDueDatePicker() {
        showsDueDatePicker = false
        Task { @MainActor in
            await Task.yield()
            titleIsFocused = true
        }
    }

#if canImport(UIKit)
    private func keyboardEndFrame(from notification: Notification) -> CGRect {
        (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
    }
#endif
}

private extension Date {
    var taskComposerLabel: String {
        formatted(.dateTime.day().month(.abbreviated))
    }
}

/// Shared top chrome for pages pushed within a primary destination.
public struct TaisaChildPageHeader: View {
    public enum Mode: Sendable {
        case back
        case detail
    }

    private let title: String
    private let mode: Mode
    private let back: @MainActor () -> Void

    public init(
        _ title: String,
        mode: Mode = .back,
        back: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.mode = mode
        self.back = back
    }

    public var body: some View {
        ZStack {
            Text(title)
                .font(TaisaTypography.childHeaderTitle.font)
                .foregroundStyle(TaisaColor.foreground.color)
                .lineLimit(1)

            HStack {
                if mode == .back {
                    TaisaSecondaryIconButton(
                        icon: .chevronLeft,
                        accessibilityLabel: "Back",
                        size: TaisaControlMetric.childNavigationControlHeight,
                        action: back
                    )
                }
                Spacer()
            }
        }
        .padding(.horizontal, TaisaSpacing.standard.rawValue)
        .frame(height: TaisaControlMetric.appBarHeight)
        .background {
            PageEdgeFade(.header)
                .ignoresSafeArea(edges: [.top, .horizontal])
        }
    }
}

/// Shared bottom backdrop and safe-area treatment for the open-chat composer.
public struct ConversationComposerChrome<Content: View, Backdrop: View>: View {
    private let content: Content
    private let backdrop: Backdrop

    public init(@ViewBuilder content: () -> Content) where Backdrop == PageEdgeFade {
        self.content = content()
        backdrop = PageEdgeFade(.navigation)
    }

    public init(
        @ViewBuilder backdrop: () -> Backdrop,
        @ViewBuilder content: () -> Content
    ) {
        self.backdrop = backdrop()
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, TaisaSpacing.standard.rawValue)
            .padding(.vertical, TaisaSpacing.section.rawValue)
            .frame(minHeight: TaisaControlMetric.conversationComposerDockHeight, alignment: .bottom)
            .background(alignment: .bottom) {
                backdrop
                    .ignoresSafeArea(edges: [.horizontal, .bottom])
                    .allowsHitTesting(false)
            }
    }
}
