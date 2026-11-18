import Foundation
import Testing
@testable import TaisaDesignSystem

@Suite("Action design-system contracts")
struct ActionComponentTests {
    @Test func buttonSizesOwnApprovedGeometry() {
        #expect(TaisaButtonSize.standard.minimumHeight == 48)
        #expect(TaisaButtonSize.standard.iconSize == 24)
        #expect(TaisaButtonSize.small.minimumHeight == 36)
        #expect(TaisaButtonSize.small.iconSize == 20)
        #expect(TaisaButton.Contract.supportsLabelContent)
        #expect(TaisaButton.Contract.supportsIconContent)
        #expect(TaisaButton.Contract.supportsIconAndLabelContent)
        #expect(TaisaButton.Contract.supportsDisabledState)
        #expect(TaisaButton.Contract.supportsSelectedState)
        #expect(TaisaButton.Contract.supportsInPlaceProgress)
        #expect(TaisaButton.Contract.supportsIntrinsicLayout)
        #expect(TaisaButton.Contract.supportsIconOnlyContent)
        #expect(TaisaButton.Contract.supportsGhostRole)
        #expect(TaisaButtonRole.ghost != .secondary)
        #expect(TaisaButtonLayout.fill != .intrinsic)
        #expect(TaisaButtonShape.circle != .capsule)
        #expect(TaisaButtonSize.small.minimumHitHeight == 44)
        #expect(TaisaEffect.taskComposerBackdropOpacity == 0.30)
    }

    @Test func graphicalDatePickerUsesPrimarySelectionAndSeparatesCancelFromCommit() {
        #expect(TaisaGraphicalDatePickerContract.tint == .primaryAction)

        let original = Date(timeIntervalSince1970: 1_800_000_000)
        let changed = Date(timeIntervalSince1970: 1_900_000_000)
        var draft = TaisaDateSelectionDraft(initial: original)
        draft.selection = changed

        #expect(draft.cancelledValue == original)
        #expect(draft.committedValue == changed)
    }

    @Test func fieldsAndBorrowedControlsHaveTypedSharedContracts() {
        #expect(TaisaFieldKind.text != .secure)
        #expect(TaisaFieldKind.multiline != .readOnly)
        #expect(TaisaFieldState.enabled != .disabled)
        #expect(TaisaFieldState.invalid(message: "Required") != .loading)
        #expect(TaisaSystemActionRole.standard != .destructive)
        #expect(TaisaSystemActionRole.cancel != .confirmation)
    }

    @Test func rowsAndStatusesNameActionMeaningWithoutRawPresentation() {
        #expect(TaisaRowEmphasis.standard != .attention)
        #expect(TaisaStatusRole.active != .completed)
        #expect(TaisaStatusRole.dropped != .overdue)
        #expect(TaisaStatusRole.reopened != .warning)
    }

    @Test func centralCatalogCoversApprovedActionConcepts() {
        let concepts: [CentralIconName] = [
            .action,
            .checklist,
            .planning,
            .add,
            .incomplete,
            .completeAction,
            .completed,
            .edit,
            .drop,
            .delete,
            .undo,
            .evidence,
            .history,
            .goal,
            .milestone,
            .warning,
            .refresh,
            .recovery,
            .insights,
            .testflight,
        ]
        #expect(Set(concepts.map(String.init(describing:))).count == concepts.count)
    }

    @Test func taskEmptyStateOwnsTheApprovedSharedComposition() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaTaskEmptyStateCard.swift"),
            encoding: .utf8
        )

        #expect(source.contains("public struct TaisaTaskEmptyStateCard"))
        #expect(source.contains("CentralIcon(.planning)"))
        #expect(source.contains("TaisaColor.subtleSurface.color"))
        #expect(source.contains("TaisaRadius.taskGroup"))
        #expect(source.contains("TaisaButton("))
        #expect(source.contains("role: .secondary"))
        #expect(source.contains("label: \"Add a task\""))
        #expect(source.contains("icon: .add"))
        #expect(source.contains("size: .small"))
        #expect(source.contains("layout: .intrinsic"))
    }

    @Test func sharedActionComponentsExposeOnePublicEntryPath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = root.appendingPathComponent("Sources/TaisaDesignSystem")

        let field = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaField.swift"), encoding: .utf8)
        let controls = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaSystemControls.swift"), encoding: .utf8)
        let pressable = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaPressable.swift"), encoding: .utf8)
        let menu = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaMenu.swift"), encoding: .utf8)
        let toolbar = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaToolbarAction.swift"), encoding: .utf8)
        let dialog = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaConfirmationDialog.swift"), encoding: .utf8)
        let secondaryIcon = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaSecondaryIconButton.swift"), encoding: .utf8)
        let secondaryCapsule = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaSecondaryCapsuleButton.swift"), encoding: .utf8)
        let row = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaRow.swift"), encoding: .utf8)
        let status = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaStatus.swift"), encoding: .utf8)

        #expect(field.contains("public struct TaisaField"))
        #expect(field.contains("public struct TaisaDateField"))
        #expect(field.contains(".accessibilityLabel(title)"))
        #expect(controls.contains("public struct TaisaPicker"))
        #expect(controls.contains("public struct TaisaNavigationRow"))
        #expect(!controls.contains("Button("))
        #expect(menu.contains("public struct TaisaMenu"))
        #expect(toolbar.contains("public struct TaisaToolbarAction"))
        #expect(dialog.contains("public struct TaisaConfirmationDialog"))
        #expect(secondaryIcon.contains("public struct TaisaSecondaryIconButton"))
        #expect(secondaryCapsule.contains("public struct TaisaSecondaryCapsuleButton"))
        #expect(pressable.contains("public struct TaisaPressable"))
        #expect(pressable.contains("@ViewBuilder label"))
        #expect(row.contains("public struct TaisaRow"))
        #expect(status.contains("public struct TaisaStatusMark"))
        #expect(status.contains("public struct TaisaStatusSurface"))

        for source in [field, controls, row, status] {
            #expect(!source.contains("systemImage:"))
            #expect(!source.contains("Image(systemName:"))
        }
    }
}
