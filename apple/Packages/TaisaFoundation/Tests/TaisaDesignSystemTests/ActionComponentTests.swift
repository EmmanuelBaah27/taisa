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
        #expect(TaisaButton.Contract.supportsSemanticIconColor)
        #expect(TaisaButtonRole.ghost != .secondary)
        #expect(TaisaButtonLayout.fill != .intrinsic)
        #expect(TaisaButtonShape.circle != .capsule)
        #expect(TaisaButtonSize.small.minimumHitHeight == 44)
        #expect(TaisaButtonRole.primary.labelTypography == .buttonLabel)
        #expect(TaisaButtonRole.secondary.labelTypography == .buttonLabel)
        #expect(TaisaButtonRole.ghost.labelTypography == .buttonLabel)
        #expect(TaisaButtonRole.destructive.labelTypography == .buttonLabel)
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
        #expect(TaisaFieldLabelPresentation.visible != .placeholderOnly)
        #expect(TaisaFieldContract.background == .subtleSurface)
        #expect(TaisaSystemActionRole.standard != .destructive)
        #expect(TaisaSystemActionRole.cancel != .confirmation)
    }

    @Test func secondaryButtonsOwnBorderAndOptionalFloatingElevation() {
        #expect(TaisaSecondaryButtonElevation.inline != .floating)
        #expect(TaisaSecondaryButtonContract.borderColor == .border)
        #expect(!TaisaSecondaryButtonContract.inlineHasAuthoredDecoration)
        #expect(TaisaSecondaryButtonContract.floatingShadowOpacity > 0)
        #expect(TaisaSecondaryButtonContract.floatingShadowRadius > 0)
    }

    @Test func taskTitleFieldStopsInputAtTheSuppliedCharacterLimit() {
        let overlongTitle = String(repeating: "a", count: 121)

        #expect(TaisaTaskTitleFieldContract.limited(overlongTitle).count == 120)
        #expect(TaisaTaskTitleFieldContract.limited("Plan launch") == "Plan launch")
    }

    @Test func expandableSheetOwnsApprovedTaskDetailPresentation() {
        #expect(TaisaExpandableSheetContract.initialPosition == .medium)
        #expect(TaisaExpandableSheetContract.positions == [.medium, .large])
        #expect(TaisaExpandableSheetContract.showsDragIndicator)
    }

    @Test func taskDetailActionsUseSharedSemanticContracts() {
        #expect(TaisaColor.completed.hex == "#04851A")
        #expect(TaisaGroupedIconActionsContract.actionCount == 2)
        #expect(TaisaGroupedIconActionsContract.iconSize == 24)
        #expect(TaisaGroupedIconActionsContract.minimumHitSize == 44)
        #expect(TaisaGroupedIconActionsContract.controlHeight == TaisaControlMetric.headerActionHeight)
        #expect(TaisaGroupedIconActionsContract.usesSharedSecondaryIconButtons)
        #expect(TaisaGroupedIconActionRole.neutral != .destructive)
    }

    @Test func groupedTaskActionsReuseClearGlassSecondaryButtons() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaGroupedIconActions.swift"),
            encoding: .utf8
        )

        #expect(source.contains("TaisaSecondaryIconButton("))
        #expect(source.contains("size: TaisaGroupedIconActionsContract.controlHeight"))
        #expect(!source.contains(".background(TaisaColor.background.color"))
        #expect(!source.contains("Capsule().stroke"))
        #expect(!source.contains(".shadow("))
    }

    @Test func rowsAndStatusesNameActionMeaningWithoutRawPresentation() {
        #expect(TaisaRowEmphasis.standard != .attention)
        #expect(TaisaStatusRole.active != .completed)
        #expect(TaisaStatusRole.dropped != .overdue)
        #expect(TaisaStatusRole.reopened != .warning)
        #expect(TaisaTaskRowContract.titleLineLimit == 2)
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

    @Test func dismissBackdropRequiresATapThatBeginsOnTheBackdrop() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaDismissBackdrop.swift"),
            encoding: .utf8
        )

        #expect(source.contains("public struct TaisaDismissBackdrop"))
        #expect(source.contains("SpatialTapGesture()"))
        #expect(source.contains("TaisaEffect.taskComposerBackdropOpacity"))
        #expect(!source.contains("Button("))
        #expect(!source.contains("Task.sleep"))
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
