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
        ]
        #expect(Set(concepts.map(String.init(describing:))).count == concepts.count)
    }

    @Test func sharedActionComponentsExposeOnePublicEntryPath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = root.appendingPathComponent("Sources/TaisaDesignSystem")

        let field = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaField.swift"), encoding: .utf8)
        let controls = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaSystemControls.swift"), encoding: .utf8)
        let row = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaRow.swift"), encoding: .utf8)
        let status = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaStatus.swift"), encoding: .utf8)

        #expect(field.contains("public struct TaisaField"))
        #expect(field.contains("public struct TaisaDateField"))
        #expect(controls.contains("public struct TaisaPicker"))
        #expect(controls.contains("public struct TaisaMenu"))
        #expect(controls.contains("public struct TaisaNavigationRow"))
        #expect(controls.contains("public struct TaisaToolbarAction"))
        #expect(controls.contains("public struct TaisaConfirmationDialog"))
        #expect(row.contains("public struct TaisaRow"))
        #expect(status.contains("public struct TaisaStatusMark"))
        #expect(status.contains("public struct TaisaStatusSurface"))

        for source in [field, controls, row, status] {
            #expect(!source.contains("systemImage:"))
            #expect(!source.contains("Image(systemName:"))
        }
    }
}
