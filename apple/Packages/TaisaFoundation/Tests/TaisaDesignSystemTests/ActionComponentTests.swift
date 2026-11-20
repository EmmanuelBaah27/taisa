import Foundation
import SwiftUI
import Testing
@testable import TaisaDesignSystem

@Suite("Action design-system contracts")
struct ActionComponentTests {
    @Test func buttonSizesOwnApprovedGeometry() {
        #expect(TaisaButtonSize.allCases == [.standard, .small])
        #expect(TaisaButtonSize.standard.visualSize == 48)
        #expect(TaisaButtonSize.small.visualSize == 36)
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

    @Test func everyAuthoredButtonRoleUsesTheExactSharedSurface() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let button = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaButton.swift"),
            encoding: .utf8
        )
        let surface = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaSecondaryButtonSurface.swift"),
            encoding: .utf8
        )
        let control = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaButtonControl.swift"),
            encoding: .utf8
        )

        #expect(button.contains("TaisaButtonStyle(role: effectiveRole, shape: shape, size: size)"))
        #expect(control.contains(".taisaButtonSurface(role: effectiveRole, size: style.size, shape: style.shape)"))
        #expect(surface.contains("case .primary:"))
        #expect(surface.contains("case .secondary, .ghost, .destructive:"))
        #expect(surface.contains(".tint(TaisaColor.primaryAction.color)"))
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
        #expect(TaisaRadius.listInterior.rawValue == 2)
        #expect(TaisaStatusRole.active != .completed)
        #expect(TaisaStatusRole.dropped != .overdue)
        #expect(TaisaStatusRole.reopened != .warning)
    }

    @Test @MainActor func sharedPressableSupportsCustomLabelsAndInteractiveRows() {
        _ = TaisaPressable(role: .destructive, action: {}) {
            TaisaText(role: .body, content: "Remove")
        }
        _ = TaisaRow(title: "Open action", supporting: "Due today", metadata: "Origin: manual", icon: .action, action: {})
        #expect(TaisaNavigationRow.trailingIconRotationDegrees(.chevronLeft) == 180)
        #expect(TaisaNavigationRow.trailingIconRotationDegrees(.profileChevron) == 0)
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
            .refresh,
            .recovery,
            .insights,
            .testflight,
        ]
        #expect(Set(concepts.map(String.init(describing:))).count == concepts.count)
    }

    @Test func primaryNavigationUsesTheApprovedInactiveIconColor() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/PrimaryNavigation.swift"),
            encoding: .utf8
        )

        #expect(source.contains("visualSelection == item ? .foreground : .inactiveForeground"))
    }

    @Test func taskRowsAndSheetsUseApprovedSharedSpacingAndColors() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let taskRow = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaTaskRow.swift"),
            encoding: .utf8
        )
        let sheet = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaExpandableSheet.swift"),
            encoding: .utf8
        )

        #expect(taskRow.contains("CentralIcon(.incomplete, color: .mutedForeground)"))
        #expect(sheet.contains(".padding(TaisaSpacing.content.rawValue)"))
    }

    @Test func profileSummaryKeepsTheApprovedSharedVisualContracts() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/TaisaDesignSystem/TaisaProfileComponents.swift"),
            encoding: .utf8
        )

        #expect(source.contains("TaisaProfileAvatar(name: name)"))
        #expect(source.contains("TaisaProfileIconButton("))
        #expect(!source.contains("TaisaToolbarAction(label: \"Edit profile\""))
    }

    @Test func sharedActionComponentsExposeOnePublicEntryPath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = root.appendingPathComponent("Sources/TaisaDesignSystem")

        let field = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaField.swift"), encoding: .utf8)
        let controls = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaSystemControls.swift"), encoding: .utf8)
        let menu = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaMenu.swift"), encoding: .utf8)
        let toolbar = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaToolbarAction.swift"), encoding: .utf8)
        let confirmation = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaConfirmationDialog.swift"), encoding: .utf8)
        let row = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaRow.swift"), encoding: .utf8)
        let status = try String(contentsOf: sourceRoot.appendingPathComponent("TaisaStatus.swift"), encoding: .utf8)

        #expect(field.contains("public struct TaisaField"))
        #expect(field.contains("public struct TaisaDateField"))
        #expect(field.contains(".accessibilityLabel(title)"))
        #expect(controls.contains("public struct TaisaPicker"))
        #expect(menu.contains("public struct TaisaMenu"))
        #expect(controls.contains("public struct TaisaNavigationRow"))
        #expect(
            controls.contains(".background(TaisaColor.subtleSurface.color, in: rowShape)"),
            "Navigation rows must retain the shared neutral surface when their interaction wrapper changes."
        )
        #expect(controls.contains("RoundedRectangle(cornerRadius: TaisaRadius.listInterior.rawValue)"))
        #expect(controls.contains(".foregroundStyle(TaisaColor.inactiveForeground.color)"))
        #expect(toolbar.contains("public struct TaisaToolbarAction"))
        #expect(confirmation.contains("public struct TaisaConfirmationDialog"))
        #expect(row.contains("public struct TaisaRow"))
        #expect(status.contains("public struct TaisaStatusMark"))
        #expect(status.contains("public struct TaisaStatusSurface"))

        for source in [field, controls, row, status] {
            #expect(!source.contains("systemImage:"))
            #expect(!source.contains("Image(systemName:"))
        }
    }
}
