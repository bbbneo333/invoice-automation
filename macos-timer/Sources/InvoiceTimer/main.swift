import AppKit
import Foundation
import UniformTypeIdentifiers

struct ProjectConfig: Decodable {
    let label: String
    let configPath: String
    let active: Bool
}

struct ReimbursementEntry: Decodable {
    let id: String
    let name: String
    let amount: Double
    let attachment: String?
}

struct GstIffPeriod: Decodable {
    let month: String
    let status: String
}

struct GstDashboard: Decodable {
    let scheme: String
    let iffEnabled: Bool
    let defaultPeriod: String?
    let periods: [GstDashboardPeriod]
    let preferences: [GstDashboardPreference]
    let inputMonths: [GstInputMonth]
}

struct GstDashboardPreference: Decodable {
    let quarterStartMonth: String
    let quarterLabel: String
    let scheme: String
    let iffEnabled: Bool
    let locked: Bool
    let lockReason: String?
}

struct GstDashboardPeriod: Decodable {
    let month: String
    let quarterLabel: String
    let scheme: String
    let iffEnabled: Bool
    let kind: String
    let actionTitle: String
    let status: String
    let locked: Bool
    let canGenerate: Bool
    let outputPath: String?
    let generatedAt: String?
    let filedAt: String?
    let amounts: GstDashboardAmounts
    let invoices: [GstDashboardInvoice]
    let checklist: [GstChecklistItem]
}

struct GstChecklistItem: Decodable {
    let id: String
    let title: String
    let status: String
    let action: String
    let dueDate: String?
    let availableDate: String?
    let recommendedDate: String?
    let generatedAt: String?
    let completedAt: String?
    let invoiceCount: Int?
    let foundCount: Int?
    let missingCount: Int?
    let carriedInCount: Int?
    let resolvedLaterCount: Int?
    let ineligibleCount: Int?
    let portalInvoiceCount: Int?
    let matchedCount: Int?
    let importedCount: Int?
    let ambiguousCount: Int?
    let missingLocalCount: Int?
    let previousBillsResolvedCount: Int?
    let acceptedCount: Int?
    let rejectedCount: Int?
    let pendingCount: Int?
    let noActionCount: Int?
    let newCount: Int?
    let changedCount: Int?
    let removedCount: Int?
    let imsSeenCount: Int?
    let imsAwaiting2bCount: Int?
    let taxableValue: Double?
    let gstAmount: Double?
    let effectiveInputGst: Double?
    let estimatedBalance: Double?
}

struct GstDashboardAmounts: Decodable {
    let invoiceCount: Int
    let taxableValue: Double
    let igst: Double
    let cgst: Double
    let sgst: Double
    let utgst: Double
    let cess: Double
    let outputTax: Double
    let invoiceValue: Double
}

struct GstDashboardInvoice: Decodable {
    let number: String
    let date: String
    let customer: String
    let taxableValue: Double
    let taxTotal: Double
    let totalValue: Double
}

struct GstInputMonth: Decodable {
    let month: String
    let quarterLabel: String
    let normalGst: Double
    let effectiveGst: Double
    let totalAmount: Double
    let invoiceCount: Int
    let foundCount: Int
    let missingCount: Int
    let carriedInCount: Int
    let carriedInGst: Double
    let resolvedLaterCount: Int
    let pendingCount: Int
    let pendingGst: Double
    let ineligibleCount: Int
    let imsSeenCount: Int
    let imsAwaiting2bCount: Int
}

struct GstInputBillMonth: Decodable {
    let month: String
    let quarterLabel: String
    let normalGst: Double
    let effectiveGst: Double
    let totalAmount: Double
    let invoiceCount: Int
    let foundCount: Int
    let missingCount: Int
    let carriedInCount: Int
    let carriedInGst: Double
    let resolvedLaterCount: Int
    let pendingCount: Int
    let pendingGst: Double
    let ineligibleCount: Int
    let imsSeenCount: Int
    let imsAwaiting2bCount: Int
    let bills: [GstInputBill]
}

struct GstInputBill: Decodable {
    let id: String
    let label: String
    let date: String
    let gstAmount: String
    let totalAmount: String
    let status: String
    let foundInMonth: String?
    let carriedForward: Bool
    let supplierGstin: String?
    let supplierName: String?
    let invoiceNumber: String?
    let matchSource: String?
    let matchMethod: String?
    let itcEligibility: String?
    let imsStatus: String?
    let imsSeenInMonth: String?
    let imsImported: Bool?
}

struct ImsImportData: Decodable {
    let period: String
    let importedAt: String
    let sourceFilename: String
    let sourceFormat: String?
    let summary: ImsImportSummary
    let invoices: [ImsPortalInvoice]
}

struct ImsImportSummary: Decodable {
    let portalInvoiceCount: Int
    let matchedCount: Int
    let importedCount: Int
    let ambiguousCount: Int
    let missingLocalCount: Int
    let acceptedCount: Int
    let rejectedCount: Int
    let pendingCount: Int
    let noActionCount: Int
    let newCount: Int
    let changedCount: Int
    let removedCount: Int
    let portalGst: Double
}

struct ImsPortalInvoice: Decodable {
    let documentKey: String
    let supplierGstin: String
    let supplierName: String
    let invoiceNumber: String
    let invoiceDate: String
    let invoiceValue: Double
    let taxableValue: Double
    let gstAmount: Double
    let imsStatus: String
    let reconciliationStatus: String
    let localBillId: String?
    let candidateBillIds: [String]?
}

struct Gstr2bImportData: Decodable {
    let period: String
    let importedAt: String
    let sourceFilename: String
    let summary: Gstr2bImportSummary
    let invoices: [Gstr2bPortalInvoice]
}

struct Gstr2bImportSummary: Decodable {
    let portalInvoiceCount: Int
    let matchedCount: Int
    let importedCount: Int
    let ambiguousCount: Int
    let missingLocalCount: Int
    let previousBillsResolvedCount: Int
    let portalGst: Double
    let representedGst: Double
}

struct Gstr2bPortalInvoice: Decodable {
    let documentKey: String
    let supplierGstin: String
    let supplierName: String
    let invoiceNumber: String
    let invoiceDate: String
    let invoiceValue: Double
    let taxableValue: Double
    let gstAmount: Double
    let itcAvailable: Bool
    let reconciliationStatus: String
    let localBillId: String?
    let candidateBillIds: [String]?
}

struct TimeLogStatus: Decodable {
    let projectLabel: String
    let projectConfigPath: String
    let projects: [ProjectConfig]
    let month: String
    let currentMonth: String
    let previousMonth: String
    let date: String
    let workday: String
    let status: String
    let startedAt: String?
    let currentStartedAt: String?
    let elapsedSeconds: Double
    let elapsedMinutes: Double
    let elapsedHours: Double
    let monthlyHours: Double
    let monthlyActualHours: Double
    let monthlyBilledHours: Double
    let workingDays: Int
    let averageHoursPerWorkingDay: Double
    let targetHours: Double
    let targetRemainingHours: Double
    let daysToTarget: Int
    let dailyTargetHours: Double
    let todayHours: Double
    let dailyTargetRemainingHours: Double
    let dailyOvertimeHours: Double
    let dailyTargetFinishAt: String?
    let dailyTargetAchieved: Bool
    let errorLogPath: String
    let logPath: String
    let statePath: String
    let outputDir: String
    let currentReimbursements: [ReimbursementEntry]
    let previousReimbursements: [ReimbursementEntry]
    let gstFilingScheme: String
    let gstIffEnabled: Bool
    let gstQuarterLabel: String
    let gstQuarterEndMonth: String
    let gstPreviousQuarterLabel: String
    let gstPreviousQuarterEndMonth: String
    let gstIffPeriods: [GstIffPeriod]
}

struct DailyHours: Decodable {
    let month: String
    let rows: [DailyHourRow]
    let totalHours: Double
    let totalActualHours: Double
    let totalBilledHours: Double
    let workingDays: Int
    let averageHoursPerWorkingDay: Double
    let targetHours: Double
    let targetRemainingHours: Double
    let daysToTarget: Int
    let dailyTargetHours: Double
}

struct DailyHourRow: Decodable {
    let date: String
    let hours: Double
    let actualHours: Double
    let billedHours: Double
    let source: String
    let timerHours: Double
    let manualHours: Double?
    let note: String?
}

struct DailyHourDraft {
    var source: String
    var actualHours: String
    var billedHours: String
    var note: String

    init(row: DailyHourRow) {
        source = row.source
        actualHours = String(format: "%.2f", row.timerHours)
        billedHours = String(format: "%.2f", row.billedHours)
        note = row.note ?? ""
    }
}

final class ReimbursementReference: NSObject {
    let month: String
    let id: String?
    let name: String?

    init(month: String, id: String? = nil, name: String? = nil) {
        self.month = month
        self.id = id
        self.name = name
    }
}

final class DirtyRowView: NSTableRowView {
    var isDirtyRow = false

    override func drawBackground(in dirtyRect: NSRect) {
        if isDirtyRow && !isSelected {
            NSColor.systemYellow.withAlphaComponent(0.16).setFill()
            dirtyRect.fill()
            return
        }

        super.drawBackground(in: dirtyRect)
    }
}

final class SaveDayButton: NSButton {
    var date: String = ""
    weak var hoursField: NSTextField?
    weak var sourceMenu: NSPopUpButton?
    weak var noteField: NSTextField?
}

final class TimeLogClient {
    private static let toolDirectory: URL = {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Backend", isDirectory: true))
        }

        // Development-only overrides and checkout locations.
        if let configured = ProcessInfo.processInfo.environment["INVOICE_AUTOMATION_HOME"],
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(URL(fileURLWithPath: configured, isDirectory: true))
        }

        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        candidates.append(currentDirectory)
        candidates.append(currentDirectory.deletingLastPathComponent())

        // `swift run` and older development bundles use the checkout directly.
        let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent()
        candidates.append(
            bundleParent
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        )

        if let directory = candidates.first(where: {
            fileManager.fileExists(atPath: $0.appendingPathComponent("src/time_log.rb").path)
        }) {
            return directory.standardizedFileURL
        }

        // Preserve a useful path in the eventual process error message.
        return candidates.first ?? currentDirectory
    }()

    private let toolDirectory = TimeLogClient.toolDirectory
    static let errorLogURL: URL = {
        let environment = ProcessInfo.processInfo.environment
        if let configured = environment["INVOICE_AUTOMATION_ERROR_LOG"], !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }
        if let configuredDirectory = environment["INVOICE_AUTOMATION_LOG_DIR"], !configuredDirectory.isEmpty {
            return URL(fileURLWithPath: configuredDirectory, isDirectory: true).appendingPathComponent("error.log")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/InvoiceTimer", isDirectory: true)
            .appendingPathComponent("error.log")
    }()

    static func appendError(source: String, message: String) {
        do {
            try FileManager.default.createDirectory(
                at: errorLogURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let entry = "[\(timestamp)] \(source)\n\(message)\n---\n"
            let data = Data(entry.utf8)
            if FileManager.default.fileExists(atPath: errorLogURL.path) {
                let handle = try FileHandle(forWritingTo: errorLogURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: errorLogURL)
            }
        } catch {
            // Logging must never break the menu bar app.
        }
    }

    static func ensureErrorLogFile() {
        do {
            try FileManager.default.createDirectory(
                at: errorLogURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: errorLogURL.path) {
                try Data().write(to: errorLogURL)
            }
        } catch {
            // Logging must never break the menu bar app.
        }
    }

    private func runData(_ command: String, _ arguments: [String] = []) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ruby", "src/time_log.rb", command] + arguments
        process.currentDirectoryURL = toolDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            Self.appendError(source: "InvoiceTimer process", message: "command=\(command)\n\(error.localizedDescription)")
            throw error
        }
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let error = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: error, encoding: .utf8) ?? "Unknown time-log error"
            Self.appendError(source: "InvoiceTimer command", message: "command=\(command)\narguments=\(arguments.joined(separator: " "))\n\(message)")
            throw NSError(domain: "InvoiceTimer.TimeLog", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }

        return output
    }

    func run(_ command: String, _ arguments: [String] = []) throws -> TimeLogStatus {
        let output = try runData(command, arguments)
        return try JSONDecoder().decode(TimeLogStatus.self, from: output)
    }

    func dailyHours(month: String? = nil) throws -> DailyHours {
        let output = try runData("daily-hours", month.map { [$0] } ?? [])
        return try JSONDecoder().decode(DailyHours.self, from: output)
    }

    func gstDashboard() throws -> GstDashboard {
        let output = try runData("gst-dashboard")
        return try JSONDecoder().decode(GstDashboard.self, from: output)
    }

    func importGstr2b(period: String, path: String) throws -> Gstr2bImportData {
        let output = try runData("import-gstr2b", [period, path])
        return try JSONDecoder().decode(Gstr2bImportData.self, from: output)
    }

    func gstr2bImport(period: String) throws -> Gstr2bImportData {
        let output = try runData("gstr2b-import", [period])
        return try JSONDecoder().decode(Gstr2bImportData.self, from: output)
    }

    func importIms(period: String, path: String) throws -> ImsImportData {
        let output = try runData("import-ims", [period, path])
        return try JSONDecoder().decode(ImsImportData.self, from: output)
    }

    func imsImport(period: String) throws -> ImsImportData {
        let output = try runData("ims-import", [period])
        return try JSONDecoder().decode(ImsImportData.self, from: output)
    }

    func gstBills(month: String) throws -> GstInputBillMonth {
        let output = try runData("gst-bills", [month])
        return try JSONDecoder().decode(GstInputBillMonth.self, from: output)
    }

    func addGstBill(month: String, label: String, date: String, gstAmount: String, totalAmount: String, status: String, foundMonth: String?) throws -> GstInputBillMonth {
        var arguments = [month, label, date, gstAmount, totalAmount, status]
        if status == "found", let foundMonth { arguments.append(foundMonth) }
        let output = try runData("add-gst-bill", arguments)
        return try JSONDecoder().decode(GstInputBillMonth.self, from: output)
    }

    func updateGstBill(month: String, bill: GstInputBill, label: String, date: String, gstAmount: String, totalAmount: String, status: String, foundMonth: String?) throws -> GstInputBillMonth {
        var arguments = [month, bill.id, label, date, gstAmount, totalAmount, status]
        if status == "found", let foundMonth { arguments.append(foundMonth) }
        let output = try runData("update-gst-bill", arguments)
        return try JSONDecoder().decode(GstInputBillMonth.self, from: output)
    }

    func deleteGstBill(month: String, id: String) throws -> GstInputBillMonth {
        let output = try runData("delete-gst-bill", [month, id])
        return try JSONDecoder().decode(GstInputBillMonth.self, from: output)
    }

    func setDay(month: String? = nil, date: String, source: String, actualHours: String = "", billedHours: String = "", note: String = "") throws -> DailyHours {
        let prefix = month.map { [$0] } ?? []
        let output = try runData("set-day", prefix + [date, source, actualHours, billedHours, note])
        return try JSONDecoder().decode(DailyHours.self, from: output)
    }

    func deleteDay(month: String? = nil, date: String) throws -> DailyHours {
        let prefix = month.map { [$0] } ?? []
        let output = try runData("delete-day", prefix + [date])
        return try JSONDecoder().decode(DailyHours.self, from: output)
    }

    func setTarget(month: String? = nil, hours: String) throws -> DailyHours {
        let prefix = month.map { [$0] } ?? []
        let output = try runData("set-target", prefix + [hours])
        return try JSONDecoder().decode(DailyHours.self, from: output)
    }

    func setDailyTarget(month: String? = nil, hours: String) throws -> DailyHours {
        let prefix = month.map { [$0] } ?? []
        let output = try runData("set-daily-target", prefix + [hours])
        return try JSONDecoder().decode(DailyHours.self, from: output)
    }
}

@MainActor
final class DailyHoursWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let client = TimeLogClient()
    private var monthLabel = ""
    private let tableView = NSTableView()
    private let targetField = NSTextField(string: "")
    private let dailyTargetField = NSTextField(string: "")
    private let workingDaysLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let targetLabel = NSTextField(labelWithString: "")
    private var daily: DailyHours?
    private var drafts: [String: DailyHourDraft] = [:]
    private var dirtyDates = Set<String>()

    convenience init(monthLabel: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit - \(monthLabel)"
        self.init(window: window)
        self.monthLabel = monthLabel
        buildUI()
        reload()
    }

    func setMonth(_ monthLabel: String) {
        guard self.monthLabel != monthLabel else {
            reload()
            return
        }

        self.monthLabel = monthLabel
        window?.title = "Edit - \(monthLabel)"
        drafts.removeAll()
        dirtyDates.removeAll()
        reload()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])

        let targetBar = NSStackView()
        targetBar.orientation = .horizontal
        targetBar.alignment = .centerY
        targetBar.spacing = 8
        let targetTitle = NSTextField(labelWithString: "Monthly target")
        targetField.placeholderString = "0"
        targetField.alignment = .right
        targetField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let dailyTargetTitle = NSTextField(labelWithString: "Daily target")
        dailyTargetField.placeholderString = "8"
        dailyTargetField.alignment = .right
        dailyTargetField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let saveTargetButton = NSButton(title: "Save Targets", target: self, action: #selector(saveTargets))
        targetBar.addArrangedSubview(targetTitle)
        targetBar.addArrangedSubview(targetField)
        targetBar.addArrangedSubview(dailyTargetTitle)
        targetBar.addArrangedSubview(dailyTargetField)
        targetBar.addArrangedSubview(saveTargetButton)
        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        targetBar.addArrangedSubview(topSpacer)
        root.addArrangedSubview(targetBar)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.headerView = NSTableHeaderView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 32
        addColumn("date", "Date", 90)
        addColumn("day", "Day", 64)
        addColumn("timer", "Timer", 78)
        addColumn("billed", "Billed", 78)
        addColumn("source", "Source", 95)
        addColumn("note", "Note", 160)
        addColumn("actions", "", 132)
        scroll.documentView = tableView
        root.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true

        let footer = NSStackView()
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 6

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10
        let addButton = NSButton(title: "Add Day", target: self, action: #selector(addDay))
        let saveAllButton = NSButton(title: "Save All", target: self, action: #selector(saveAllRows))
        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshRows))
        actions.addArrangedSubview(addButton)
        actions.addArrangedSubview(saveAllButton)
        actions.addArrangedSubview(refreshButton)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actions.addArrangedSubview(spacer)
        footer.addArrangedSubview(actions)
        footer.addArrangedSubview(workingDaysLabel)
        footer.addArrangedSubview(summaryLabel)
        footer.addArrangedSubview(targetLabel)
        root.addArrangedSubview(footer)
    }

    private func addColumn(_ identifier: String, _ title: String, _ width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = width
        tableView.addTableColumn(column)
    }

    private func reload() {
        do {
            daily = try client.dailyHours(month: monthLabel)
            mergeDraftsFromSavedRows()
            render()
        } catch {
            summaryLabel.stringValue = "Error: \(error.localizedDescription)"
        }
    }

    private func mergeDraftsFromSavedRows() {
        guard let rows = daily?.rows else { return }
        let dates = Set(rows.map(\.date))
        drafts = drafts.filter { dates.contains($0.key) }
        dirtyDates = dirtyDates.filter { dates.contains($0) }

        for row in rows where !dirtyDates.contains(row.date) {
            drafts[row.date] = DailyHourDraft(row: row)
        }
    }

    private func savedRow(date: String) -> DailyHourRow? {
        daily?.rows.first { $0.date == date }
    }

    private func draft(for row: DailyHourRow) -> DailyHourDraft {
        if let draft = drafts[row.date] { return draft }

        let draft = DailyHourDraft(row: row)
        drafts[row.date] = draft
        return draft
    }

    private func markDirty(date: String) {
        dirtyDates.insert(date)
        if let rowIndex = daily?.rows.firstIndex(where: { $0.date == date }) {
            if let rowView = tableView.rowView(atRow: rowIndex, makeIfNecessary: false) as? DirtyRowView {
                rowView.isDirtyRow = true
                rowView.needsDisplay = true
            }
        }
    }

    private func rowDate(_ rowIndex: Int) -> String? {
        guard let rows = daily?.rows, rows.indices.contains(rowIndex) else { return nil }
        return rows[rowIndex].date
    }

    private func render() {
        tableView.reloadData()
        let actualHours = daily?.totalActualHours ?? daily?.totalHours ?? 0
        let billedHours = daily?.totalBilledHours ?? 0
        let days = daily?.workingDays ?? 0
        let target = daily?.targetHours ?? 0
        let dailyTarget = daily?.dailyTargetHours ?? 8
        let timerAverage = days > 0 ? actualHours / Double(days) : 0
        let billedAverage = days > 0 ? billedHours / Double(days) : 0

        targetField.stringValue = target > 0 ? String(format: "%.2f", target) : ""
        dailyTargetField.stringValue = String(format: "%.2f", dailyTarget)
        workingDaysLabel.stringValue = "Working Days: \(days)"
        summaryLabel.stringValue = footerSummary(
            title: "Timer",
            total: actualHours,
            target: target,
            average: timerAverage
        )
        targetLabel.stringValue = footerSummary(
            title: "Billed",
            total: billedHours,
            target: target,
            average: billedAverage
        )
    }

    private func footerSummary(title: String, total: Double, target: Double, average: Double) -> String {
        var summary = String(format: "%@: %.2fh", title, total)

        if target > 0 {
            let delta = total - target
            summary += String(format: " (%+.2fh)", delta)
        }

        summary += String(format: ", avg/day: %.2fh", average)

        let remaining = target - total
        if target > 0, remaining > 0, average > 0 {
            let daysToTarget = Int(ceil(remaining / average))
            summary += " (\(daysToTarget) days to target)"
        }

        return summary
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        daily?.rows.count ?? 0
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = DirtyRowView()
        if let date = rowDate(row) {
            rowView.isDirtyRow = dirtyDates.contains(date)
        }
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row rowIndex: Int) -> NSView? {
        guard let row = daily?.rows[rowIndex], let id = tableColumn?.identifier.rawValue else { return nil }
        let draft = draft(for: row)

        switch id {
        case "date":
            return tableText(displayDate(row.date), color: .labelColor)
        case "day":
            return tableText(displayDay(row.date), color: .secondaryLabelColor)
        case "timer":
            return tableText(String(format: "%.2f", row.timerHours), color: .secondaryLabelColor)
        case "billed":
            let field = NSTextField(string: draft.billedHours)
            field.identifier = NSUserInterfaceItemIdentifier("billed")
            field.isEditable = draft.source == "manual"
            field.isEnabled = draft.source == "manual"
            field.delegate = self
            field.tag = rowIndex
            return cell(field)
        case "source":
            let menu = NSPopUpButton()
            menu.addItems(withTitles: ["timer", "manual"])
            menu.selectItem(withTitle: draft.source)
            menu.target = self
            menu.action = #selector(sourceChanged(_:))
            menu.tag = rowIndex
            return cell(menu)
        case "note":
            let field = NSTextField(string: draft.note)
            field.identifier = NSUserInterfaceItemIdentifier("note")
            field.isEditable = draft.source == "manual"
            field.isEnabled = draft.source == "manual"
            field.delegate = self
            field.tag = rowIndex
            return cell(field)
        case "actions":
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 6
            let save = iconButton(symbolName: "tray.and.arrow.down", fallbackTitle: "S", action: #selector(saveTableRow(_:)), row: rowIndex, tooltip: "Save")
            let reset = iconButton(symbolName: "arrow.counterclockwise", fallbackTitle: "R", action: #selector(resetTableRow(_:)), row: rowIndex, tooltip: "Reset")
            let delete = iconButton(symbolName: "trash", fallbackTitle: "D", action: #selector(deleteTableRow(_:)), row: rowIndex, tooltip: "Delete")
            stack.addArrangedSubview(save)
            stack.addArrangedSubview(reset)
            stack.addArrangedSubview(delete)
            return cell(stack)
        default:
            return nil
        }
    }

    private func tableText(_ text: String, color: NSColor) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.textColor = color
        return cell(label)
    }

    private func iconButton(symbolName: String, fallbackTitle: String, action: Selector, row: Int, tooltip: String) -> NSButton {
        let button: NSButton
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip) {
            button = NSButton(image: image, target: self, action: action)
        } else {
            button = NSButton(title: fallbackTitle, target: self, action: action)
        }
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.tag = row
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func cell(_ content: NSView) -> NSTableCellView {
        let view = NSTableCellView()
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            content.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    private func displayDate(_ isoDate: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        formatter.dateFormat = "MMM dd"
        return formatter.string(from: date)
    }

    private func displayDay(_ isoDate: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: isoDate) else { return "" }
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    @objc private func refreshRows() {
        reload()
    }

    @objc private func sourceChanged(_ sender: NSPopUpButton) {
        guard let row = daily?.rows[sender.tag], let source = sender.titleOfSelectedItem else { return }
        var draft = draft(for: row)
        draft.source = source
        draft.actualHours = String(format: "%.2f", row.timerHours)
        draft.billedHours = String(format: "%.2f", row.timerHours)
        if source == "timer" {
            draft.note = ""
        }
        drafts[row.date] = draft
        markDirty(date: row.date)
        tableView.reloadData(forRowIndexes: IndexSet(integer: sender.tag), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              let date = rowDate(field.tag),
              var draft = drafts[date] else {
            return
        }

        switch field.identifier?.rawValue {
        case "billed":
            draft.billedHours = field.stringValue
        case "note":
            draft.note = field.stringValue
        default:
            return
        }

        drafts[date] = draft
        markDirty(date: date)
    }

    @objc private func saveTableRow(_ sender: NSButton) {
        guard let row = daily?.rows[sender.tag] else { return }
        captureVisibleDraft(rowIndex: sender.tag)
        saveDraft(row)
    }

    @objc private func resetTableRow(_ sender: NSButton) {
        guard let row = daily?.rows[sender.tag] else { return }
        drafts[row.date] = DailyHourDraft(row: row)
        dirtyDates.remove(row.date)
        if let rowView = tableView.rowView(atRow: sender.tag, makeIfNecessary: false) as? DirtyRowView {
            rowView.isDirtyRow = false
        }
        tableView.reloadData(forRowIndexes: IndexSet(integer: sender.tag), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
    }

    private func captureVisibleDraft(rowIndex: Int) {
        guard let row = daily?.rows[rowIndex] else { return }
        var draft = draft(for: row)

        if let billedField = textField(atColumn: 3, row: rowIndex) {
            draft.billedHours = billedField.stringValue
        }

        if let noteField = textField(atColumn: 5, row: rowIndex) {
            draft.note = noteField.stringValue
        }

        drafts[row.date] = draft
    }

    private func textField(atColumn column: Int, row: Int) -> NSTextField? {
        guard let cellView = tableView.view(atColumn: column, row: row, makeIfNecessary: false) as? NSTableCellView else { return nil }
        return cellView.subviews.compactMap { $0 as? NSTextField }.first
    }

    @objc private func deleteTableRow(_ sender: NSButton) {
        guard let row = daily?.rows[sender.tag] else { return }

        let alert = NSAlert()
        alert.messageText = "Delete \(displayDate(row.date))?"
        alert.informativeText = "This removes the daily entry from the monthly time log."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            daily = try client.deleteDay(month: monthLabel, date: row.date)
            drafts.removeValue(forKey: row.date)
            dirtyDates.remove(row.date)
            mergeDraftsFromSavedRows()
            render()
        } catch {
            summaryLabel.stringValue = "Error: \(error.localizedDescription)"
        }
    }

    private func saveDraft(_ row: DailyHourRow) {
        let draft = draft(for: row)
        do {
            daily = try client.setDay(
                month: monthLabel,
                date: row.date,
                source: draft.source,
                actualHours: draft.actualHours,
                billedHours: draft.billedHours,
                note: draft.note
            )
            dirtyDates.remove(row.date)
            mergeDraftsFromSavedRows()
            render()
        } catch {
            summaryLabel.stringValue = "Error: \(error.localizedDescription)"
        }
    }

    @objc private func saveAllRows() {
        guard let rows = daily?.rows else { return }

        for rowIndex in 0..<rows.count {
            captureVisibleDraft(rowIndex: rowIndex)
        }

        let datesToSave = rows.map(\.date).filter { dirtyDates.contains($0) }
        guard !datesToSave.isEmpty else { return }

        do {
            for date in datesToSave {
                guard let row = savedRow(date: date), let draft = drafts[date] else { continue }
                daily = try client.setDay(
                    month: monthLabel,
                    date: row.date,
                    source: draft.source,
                    actualHours: draft.actualHours,
                    billedHours: draft.billedHours,
                    note: draft.note
                )
                dirtyDates.remove(date)
                mergeDraftsFromSavedRows()
            }
            render()
        } catch {
            summaryLabel.stringValue = "Error: \(error.localizedDescription)"
            render()
        }
    }

    private func save(date: String, source: String, actualHours: String, billedHours: String, note: String) {
        do {
            daily = try client.setDay(month: monthLabel, date: date, source: source, actualHours: actualHours, billedHours: billedHours, note: note)
            mergeDraftsFromSavedRows()
            render()
        } catch {
            summaryLabel.stringValue = "Error: \(error.localizedDescription)"
        }
    }

    @objc private func saveTargets() {
        do {
            daily = try client.setTarget(month: monthLabel, hours: targetField.stringValue)
            daily = try client.setDailyTarget(month: monthLabel, hours: dailyTargetField.stringValue)
            render()
        } catch {
            summaryLabel.stringValue = "Error: \(error.localizedDescription)"
        }
    }

    @objc private func addDay() {
        let alert = NSAlert()
        alert.messageText = "Add Day"
        alert.informativeText = "Choose a date and enter billed hours."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let picker = NSDatePicker(frame: NSRect(x: 0, y: 34, width: 220, height: 26))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay]
        picker.dateValue = Date()

        let hours = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        hours.placeholderString = "Billed hours, e.g. 8"

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 64))
        accessory.addSubview(picker)
        accessory.addSubview(hours)
        alert.accessoryView = accessory

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: picker.dateValue)

        do {
            daily = try client.setDay(month: monthLabel, date: date, source: "manual", actualHours: "", billedHours: hours.stringValue, note: "")
            render()
        } catch {
            summaryLabel.stringValue = "Error: \(error.localizedDescription)"
        }
    }
}

final class GstChecklistActionButton: NSButton {
    var checklistAction = ""
}

@MainActor
final class GstBillsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let client = TimeLogClient()
    private var monthLabel: String
    private var data: GstInputBillMonth?
    private let tableView = NSTableView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let editButton = NSButton(title: "Edit", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private weak var activeFoundMonthPicker: NSPopUpButton?
    var onChange: (() -> Void)?

    init(monthLabel: String) {
        self.monthLabel = monthLabel
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 430),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GST Input Bills - \(monthLabel)"
        window.minSize = NSSize(width: 620, height: 360)
        super.init(window: window)
        buildUI()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMonth(_ month: String) {
        monthLabel = month
        window?.title = "GST Input Bills - \(month)"
        reload()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])

        let note = NSTextField(wrappingLabelWithString: "Local tracking only. Found means you confirmed the bill on the GST portal; it is not verified automatically.")
        note.textColor = .secondaryLabelColor
        root.addArrangedSubview(note)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 28
        tableView.target = self
        tableView.doubleAction = #selector(editSelected)
        addColumn("label", "Label", 220)
        addColumn("date", "Date", 100)
        addColumn("gst", "GST", 100)
        addColumn("total", "Total", 110)
        addColumn("status", "Portal", 140)
        scroll.documentView = tableView
        root.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        actions.addArrangedSubview(NSButton(title: "Add Bill", target: self, action: #selector(addBill)))
        editButton.target = self
        editButton.action = #selector(editSelected)
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)
        actions.addArrangedSubview(editButton)
        actions.addArrangedSubview(deleteButton)
        actions.addArrangedSubview(NSButton(title: "Refresh", target: self, action: #selector(refreshClicked)))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actions.addArrangedSubview(spacer)
        root.addArrangedSubview(actions)
        actions.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        root.addArrangedSubview(summaryLabel)
        messageLabel.textColor = .systemRed
        root.addArrangedSubview(messageLabel)
        messageLabel.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        updateSelectionActions()
    }

    private func addColumn(_ identifier: String, _ title: String, _ width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = identifier == "label" ? 150 : width
        tableView.addTableColumn(column)
    }

    private func reload() {
        do {
            data = try client.gstBills(month: monthLabel)
            messageLabel.stringValue = ""
            render()
        } catch {
            messageLabel.stringValue = error.localizedDescription
        }
    }

    private func render() {
        tableView.reloadData()
        let normal = data?.normalGst ?? 0
        let effective = data?.effectiveGst ?? 0
        let carriedIn = data?.carriedInCount ?? 0
        let pending = data?.pendingCount ?? 0
        let ineligible = data?.ineligibleCount ?? 0
        let imsSeen = data?.imsSeenCount ?? 0
        summaryLabel.stringValue = "Recorded GST: \(money(normal))  ·  Confirmed ITC (GSTR-2B): \(money(effective))  ·  IMS seen: \(imsSeen)  ·  Carried in: \(carriedIn)  ·  Still pending: \(pending)  ·  Ineligible: \(ineligible)"
        updateSelectionActions()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        data?.bills.count ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let bill = data?.bills[row], let identifier = tableColumn?.identifier.rawValue else { return nil }
        let field = NSTextField(labelWithString: "")
        switch identifier {
        case "label": field.stringValue = bill.label
        case "date": field.stringValue = displayDate(bill.date)
        case "gst":
            field.stringValue = money(Double(bill.gstAmount) ?? 0)
            field.alignment = .right
        case "total":
            field.stringValue = money(Double(bill.totalAmount) ?? 0)
            field.alignment = .right
        case "status":
            if bill.itcEligibility == "ineligible" {
                field.stringValue = "GSTR-2B · Ineligible"
                field.textColor = .systemRed
            } else if bill.status == "found" {
                let prefix = bill.matchSource == "gstr2b" ? "Matched" : "Manual"
                field.stringValue = "\(prefix) · \(bill.foundInMonth ?? "")".trimmingCharacters(in: .whitespaces)
                field.textColor = .systemGreen
            } else if let imsStatus = bill.imsStatus {
                field.stringValue = "IMS \(displayImsStatus(imsStatus)) · Awaiting 2B"
                field.textColor = imsStatus == "rejected" ? .systemRed : .systemBlue
            } else {
                field.stringValue = bill.carriedForward ? "Pending · Carried" : "Missing"
                field.textColor = .systemOrange
            }
        default: break
        }
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelectionActions()
    }

    private func updateSelectionActions() {
        let selected = tableView.selectedRow >= 0 && tableView.selectedRow < (data?.bills.count ?? 0)
        editButton.isEnabled = selected
        deleteButton.isEnabled = selected
    }

    private var selectedBill: GstInputBill? {
        let row = tableView.selectedRow
        guard row >= 0, let bills = data?.bills, bills.indices.contains(row) else { return nil }
        return bills[row]
    }

    @objc private func addBill() {
        presentEditor(bill: nil)
    }

    @objc private func editSelected() {
        guard let bill = selectedBill else { return }
        presentEditor(bill: bill)
    }

    @objc private func deleteSelected() {
        guard let bill = selectedBill else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \(bill.label)?"
        alert.informativeText = "This removes only the local tracking record."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            data = try client.deleteGstBill(month: monthLabel, id: bill.id)
            messageLabel.stringValue = ""
            render()
            onChange?()
        } catch {
            messageLabel.stringValue = error.localizedDescription
        }
    }

    private func presentEditor(bill: GstInputBill?) {
        let alert = NSAlert()
        alert.messageText = bill == nil ? "Add GST Input Bill" : "Edit GST Input Bill"
        alert.informativeText = "Enter values from the supplier invoice. Normal confirmation comes from GSTR-2B import; use the manual override only for an exceptional reconciliation."
        alert.addButton(withTitle: bill == nil ? "Add" : "Save")
        alert.addButton(withTitle: "Cancel")

        let labelField = NSTextField(string: bill?.label ?? "")
        labelField.placeholderString = "Label"
        let datePicker = NSDatePicker()
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.dateValue = bill.flatMap { parseDate($0.date) } ?? firstDateOfMonth()
        let gstField = NSTextField(string: bill?.gstAmount ?? "")
        gstField.placeholderString = "GST amount"
        let totalField = NSTextField(string: bill?.totalAmount ?? "")
        totalField.placeholderString = "Total amount"
        let foundCheckbox = NSButton(checkboxWithTitle: "Manually confirmed in GSTR-2B", target: nil, action: nil)
        foundCheckbox.state = bill?.status == "found" ? .on : .off
        let foundMonthPicker = NSPopUpButton()
        let billDate = bill.flatMap { parseDate($0.date) } ?? firstDateOfMonth()
        foundMonthPicker.addItems(withTitles: monthChoices(from: billDate, including: bill?.foundInMonth))
        foundMonthPicker.selectItem(withTitle: bill?.foundInMonth ?? defaultFoundMonth(from: billDate))
        foundMonthPicker.isEnabled = foundCheckbox.state == .on
        foundCheckbox.target = self
        foundCheckbox.action = #selector(manualFoundChanged(_:))
        activeFoundMonthPicker = foundMonthPicker

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Label"), labelField],
            [NSTextField(labelWithString: "Date"), datePicker],
            [NSTextField(labelWithString: "GST"), gstField],
            [NSTextField(labelWithString: "Total"), totalField],
            [NSTextField(labelWithString: ""), foundCheckbox],
            [NSTextField(labelWithString: "Found in period"), foundMonthPicker]
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.frame = NSRect(x: 0, y: 0, width: 390, height: 185)
        grid.column(at: 1).width = 240
        alert.accessoryView = grid

        let response = alert.runModal()
        activeFoundMonthPicker = nil
        guard response == .alertFirstButtonReturn else { return }
        let date = isoDate(datePicker.dateValue)
        let status = foundCheckbox.state == .on ? "found" : "missing"
        let foundMonth = status == "found" ? foundMonthPicker.titleOfSelectedItem : nil
        do {
            if let bill {
                data = try client.updateGstBill(
                    month: monthLabel, bill: bill, label: labelField.stringValue,
                    date: date, gstAmount: gstField.stringValue,
                    totalAmount: totalField.stringValue, status: status, foundMonth: foundMonth
                )
            } else {
                data = try client.addGstBill(
                    month: monthLabel, label: labelField.stringValue, date: date,
                    gstAmount: gstField.stringValue, totalAmount: totalField.stringValue,
                    status: status, foundMonth: foundMonth
                )
            }
            messageLabel.stringValue = ""
            render()
            onChange?()
        } catch {
            messageLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func manualFoundChanged(_ sender: NSButton) {
        activeFoundMonthPicker?.isEnabled = sender.state == .on
    }

    @objc private func refreshClicked() {
        reload()
    }

    private func firstDateOfMonth() -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.date(from: monthLabel) ?? Date()
    }

    private func monthChoices(from startDate: Date, including existing: String?) -> [String] {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate)) ?? startDate
        var end = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        if start > end { end = start }
        if let viewedMonth = monthDate(monthLabel), viewedMonth > end { end = viewedMonth }
        if let existing, let existingDate = monthDate(existing), existingDate > end {
            end = existingDate
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        var months: [String] = []
        var cursor = start
        while cursor <= end {
            months.append(formatter.string(from: cursor))
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return months
    }

    private func monthDate(_ label: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.date(from: label)
    }

    private func defaultFoundMonth(from billDate: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let billMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: billDate)) ?? billDate
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: max(billMonth, currentMonth))
    }

    private func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func displayDate(_ value: String) -> String {
        guard let date = parseDate(value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    private func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_IN")
        formatter.currencyCode = "INR"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "₹%.2f", value)
    }

    private func displayImsStatus(_ status: String) -> String {
        status == "no_action" ? "No Action" : status.capitalized
    }
}

@MainActor
final class ImsResultsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let data: ImsImportData
    private let onManageBills: () -> Void
    private let onImportAgain: () -> Void
    private let tableView = NSTableView()

    init(data: ImsImportData, onManageBills: @escaping () -> Void, onImportAgain: @escaping () -> Void) {
        self.data = data
        self.onManageBills = onManageBills
        self.onImportAgain = onImportAgain
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 520),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.title = "IMS Reconciliation - \(data.period)"
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])

        let summary = data.summary
        let actionSummary = "\(summary.acceptedCount) accepted · \(summary.rejectedCount) rejected · \(summary.pendingCount) pending · \(summary.noActionCount) no action"
        let summaryLabel = NSTextField(wrappingLabelWithString:
            "\(summary.portalInvoiceCount) IMS records · \(summary.matchedCount) matched · \(summary.importedCount) added · \(summary.ambiguousCount) ambiguous · \(summary.missingLocalCount) local missing\n\(actionSummary) · GST \(money(summary.portalGst))\nSince previous import: \(summary.newCount) new · \(summary.changedCount) changed · \(summary.removedCount) removed · Source: \(data.sourceFilename)"
        )
        summaryLabel.font = .systemFont(ofSize: 13, weight: .medium)
        root.addArrangedSubview(summaryLabel)

        let columns: [(String, String, CGFloat)] = [
            ("supplier", "Supplier", 210), ("invoice", "Invoice", 110), ("date", "Date", 95),
            ("total", "Total", 90), ("gst", "GST", 85), ("ims", "IMS Action", 100), ("result", "Local Result", 150)
        ]
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.headerView = NSTableHeaderView()
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        root.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.addArrangedSubview(NSButton(title: "Manage Bills", target: self, action: #selector(manageBills)))
        buttons.addArrangedSubview(NSButton(title: "Import Updated IMS CSV", target: self, action: #selector(importAgain)))
        buttons.addArrangedSubview(NSButton(title: "Close", target: self, action: #selector(closeWindow)))
        root.addArrangedSubview(buttons)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { data.invoices.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        let invoice = data.invoices[row]
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        switch id {
        case "supplier": field.stringValue = invoice.supplierName.isEmpty ? invoice.supplierGstin : invoice.supplierName
        case "invoice": field.stringValue = invoice.invoiceNumber
        case "date": field.stringValue = displayDate(invoice.invoiceDate)
        case "total": field.stringValue = money(invoice.invoiceValue)
        case "gst": field.stringValue = money(invoice.gstAmount)
        case "ims": field.stringValue = invoice.imsStatus == "no_action" ? "No Action" : invoice.imsStatus.capitalized
        case "result":
            switch invoice.reconciliationStatus {
            case "matched": field.stringValue = "Matched local bill"
            case "imported": field.stringValue = "Added provisionally"
            case "ambiguous": field.stringValue = "Needs review"
            default: field.stringValue = invoice.reconciliationStatus.capitalized
            }
        default: break
        }
        return field
    }

    @objc private func manageBills() { onManageBills() }
    @objc private func importAgain() { close(); onImportAgain() }
    @objc private func closeWindow() { close() }

    private func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_IN")
        formatter.currencyCode = "INR"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "₹%.2f", value)
    }

    private func displayDate(_ isoDate: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: isoDate) else { return isoDate }
        let output = DateFormatter()
        output.locale = Locale(identifier: "en_IN")
        output.dateFormat = "d MMM yyyy"
        return output.string(from: date)
    }
}

@MainActor
final class Gstr2bResultsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let data: Gstr2bImportData
    private let onManageBills: () -> Void
    private let tableView = NSTableView()

    init(data: Gstr2bImportData, onManageBills: @escaping () -> Void) {
        self.data = data
        self.onManageBills = onManageBills
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GSTR-2B Reconciliation - \(data.period)"
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])

        let summary = data.summary
        let summaryLabel = NSTextField(wrappingLabelWithString:
            "\(summary.portalInvoiceCount) portal invoices · \(summary.matchedCount) matched · \(summary.importedCount) added · \(summary.ambiguousCount) ambiguous · \(summary.missingLocalCount) local missing\nPortal ITC \(money(summary.portalGst)) · Represented ITC \(money(summary.representedGst)) · \(summary.previousBillsResolvedCount) previous bills resolved · Source: \(data.sourceFilename)"
        )
        summaryLabel.font = .systemFont(ofSize: 13, weight: .medium)
        root.addArrangedSubview(summaryLabel)

        let columns: [(String, String, CGFloat)] = [
            ("supplier", "Supplier", 210), ("invoice", "Invoice", 110), ("date", "Date", 95),
            ("total", "Total", 90), ("gst", "GST", 85), ("itc", "ITC", 70), ("result", "Result", 170)
        ]
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.headerView = NSTableHeaderView()
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(scrollView)
        scrollView.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let manage = NSButton(title: "Manage Bills", target: self, action: #selector(manageBills))
        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        buttons.addArrangedSubview(manage)
        buttons.addArrangedSubview(close)
        root.addArrangedSubview(buttons)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { data.invoices.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        let invoice = data.invoices[row]
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        switch id {
        case "supplier": field.stringValue = invoice.supplierName.isEmpty ? invoice.supplierGstin : invoice.supplierName
        case "invoice": field.stringValue = invoice.invoiceNumber
        case "date": field.stringValue = displayDate(invoice.invoiceDate)
        case "total": field.stringValue = money(invoice.invoiceValue)
        case "gst": field.stringValue = money(invoice.gstAmount)
        case "itc": field.stringValue = invoice.itcAvailable ? "Eligible" : "No"
        case "result":
            switch invoice.reconciliationStatus {
            case "matched": field.stringValue = invoice.itcAvailable ? "Matched" : "Matched · Ineligible"
            case "imported": field.stringValue = invoice.itcAvailable ? "Added from portal" : "Added · Ineligible"
            case "ambiguous": field.stringValue = "Needs review"
            default: field.stringValue = invoice.reconciliationStatus.capitalized
            }
        default: break
        }
        return field
    }

    @objc private func manageBills() { onManageBills() }
    @objc private func closeWindow() { close() }

    private func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_IN")
        formatter.currencyCode = "INR"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "₹%.2f", value)
    }

    private func displayDate(_ isoDate: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: isoDate) else { return isoDate }
        let output = DateFormatter()
        output.locale = Locale(identifier: "en_IN")
        output.dateFormat = "d MMM yyyy"
        return output.string(from: date)
    }
}

@MainActor
final class GstDashboardWindowController: NSWindowController {
    private let client = TimeLogClient()
    private var dashboard: GstDashboard?
    private var selectedMonth: String?
    private var isWorking = false

    private let periodMenu = NSPopUpButton()
    private let schemeLabel = NSTextField(labelWithString: "")
    private let filingSchemeMenu = NSPopUpButton()
    private let iffCheckbox = NSButton(checkboxWithTitle: "Use IFF in the first two months", target: nil, action: nil)
    private let savePreferenceButton = NSButton(title: "Save Preference", target: nil, action: nil)
    private let preferenceNoteLabel = NSTextField(wrappingLabelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "GST Filing")
    private let checklistStack = NSStackView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private var billsWindow: GstBillsWindowController?
    private var imsResultsWindow: ImsResultsWindowController?
    private var gstr2bResultsWindow: Gstr2bResultsWindowController?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GST Dashboard"
        window.minSize = NSSize(width: 760, height: 560)
        self.init(window: window)
        buildUI()
        reload()
    }

    func refresh() {
        reload()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        let top = NSStackView()
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 8
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        top.addArrangedSubview(titleLabel)
        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        top.addArrangedSubview(topSpacer)
        top.addArrangedSubview(NSTextField(labelWithString: "Period"))
        periodMenu.target = self
        periodMenu.action = #selector(periodChanged)
        periodMenu.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        top.addArrangedSubview(periodMenu)
        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshClicked))
        top.addArrangedSubview(refreshButton)
        root.addArrangedSubview(top)
        top.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        schemeLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(schemeLabel)

        let preferenceBar = NSStackView()
        preferenceBar.orientation = .horizontal
        preferenceBar.alignment = .centerY
        preferenceBar.spacing = 10
        preferenceBar.addArrangedSubview(NSTextField(labelWithString: "Filing preference"))
        filingSchemeMenu.addItems(withTitles: ["Monthly", "QRMP"])
        filingSchemeMenu.target = self
        filingSchemeMenu.action = #selector(preferenceSchemeChanged)
        preferenceBar.addArrangedSubview(filingSchemeMenu)
        iffCheckbox.target = self
        iffCheckbox.action = #selector(preferenceIffChanged)
        preferenceBar.addArrangedSubview(iffCheckbox)
        savePreferenceButton.target = self
        savePreferenceButton.action = #selector(savePreference)
        preferenceBar.addArrangedSubview(savePreferenceButton)
        root.addArrangedSubview(preferenceBar)

        preferenceNoteLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(preferenceNoteLabel)
        preferenceNoteLabel.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let separator = NSBox()
        separator.boxType = .separator
        root.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let checklistTitle = NSTextField(labelWithString: "Checklist")
        checklistTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        root.addArrangedSubview(checklistTitle)

        checklistStack.orientation = .vertical
        checklistStack.alignment = .leading
        checklistStack.spacing = 8
        root.addArrangedSubview(checklistStack)
        checklistStack.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let checklistNote = NSTextField(wrappingLabelWithString: "IMS matches are provisional. Confirmed ITC (GSTR-2B) includes only GSTR-2B matches or explicit manual overrides. Confirm portal balances, adjustments and any due-date extension on the GST portal.")
        checklistNote.textColor = .secondaryLabelColor
        checklistNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        root.addArrangedSubview(checklistNote)
        checklistNote.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let flexibleSpace = NSView()
        flexibleSpace.setContentHuggingPriority(.defaultLow, for: .vertical)
        root.addArrangedSubview(flexibleSpace)

        messageLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(messageLabel)
        messageLabel.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

    }

    private var selectedPeriod: GstDashboardPeriod? {
        guard let periods = dashboard?.periods, !periods.isEmpty else { return nil }
        guard let month = periodMenu.selectedItem?.representedObject as? String else {
            return dashboard?.defaultPeriod.flatMap { target in periods.first { $0.month == target } } ?? periods.first
        }
        return periods.first { $0.month == month } ?? periods.first
    }

    private var selectedPreference: GstDashboardPreference? {
        guard let quarterLabel = selectedPeriod?.quarterLabel else { return nil }
        return dashboard?.preferences.first { $0.quarterLabel == quarterLabel }
    }

    private var selectedInputMonths: [GstInputMonth] {
        guard let quarterLabel = selectedPeriod?.quarterLabel else { return [] }
        return dashboard?.inputMonths.filter { $0.quarterLabel == quarterLabel } ?? []
    }

    private func reload() {
        do {
            let previous = selectedMonth
            dashboard = try client.gstDashboard()
            let target = previous ?? dashboard?.defaultPeriod
            periodMenu.removeAllItems()
            periodMenu.menu?.autoenablesItems = false
            let periods = dashboard?.periods ?? []
            let currentMonth = Calendar(identifier: .gregorian).date(from: Calendar(identifier: .gregorian).dateComponents([.year, .month], from: Date())) ?? Date()
            let active = periods.filter { (monthDate($0.month) ?? currentMonth) >= currentMonth }.sorted { (monthDate($0.month) ?? currentMonth) < (monthDate($1.month) ?? currentMonth) }
            let past = periods.filter { (monthDate($0.month) ?? currentMonth) < currentMonth }.sorted { (monthDate($0.month) ?? currentMonth) > (monthDate($1.month) ?? currentMonth) }
            for period in active {
                addPeriodMenuItem(period, currentMonth: currentMonth)
            }
            if !past.isEmpty {
                periodMenu.menu?.addItem(.separator())
                let heading = NSMenuItem(title: "Past periods", action: nil, keyEquivalent: "")
                heading.isEnabled = false
                periodMenu.menu?.addItem(heading)
                for period in past {
                    addPeriodMenuItem(period, currentMonth: currentMonth)
                }
            }
            if let target, let item = periodMenu.itemArray.first(where: { ($0.representedObject as? String) == target }) {
                periodMenu.select(item)
            }
            selectedMonth = selectedPeriod?.month
            messageLabel.stringValue = ""
            render()
        } catch {
            messageLabel.textColor = .systemRed
            messageLabel.stringValue = error.localizedDescription
            setActionsEnabled(false)
        }
    }

    private func addPeriodMenuItem(_ period: GstDashboardPeriod, currentMonth: Date) {
        let periodDate = monthDate(period.month)
        let paymentComplete = period.checklist.contains { $0.id == "payment" && $0.status == "complete" }
        let status: String
        if paymentComplete {
            status = " - Paid"
        } else if period.kind == "iff" && period.status == "filed" {
            status = " - IFF Filed"
        } else if period.status == "filed" {
            status = " - Filed"
        } else {
            status = ""
        }
        let current = periodDate == currentMonth ? " - Current" : ""
        let item = NSMenuItem(title: "\(period.month)\(current)\(status)", action: nil, keyEquivalent: "")
        item.representedObject = period.month
        periodMenu.menu?.addItem(item)
    }

    private func monthDate(_ label: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.date(from: label)
    }

    private func render() {
        guard dashboard != nil, let period = selectedPeriod else {
            schemeLabel.stringValue = "No GST filing periods are available."
            checklistStack.arrangedSubviews.forEach { view in
                checklistStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            setActionsEnabled(false)
            return
        }

        selectedMonth = period.month
        schemeLabel.stringValue = "\(period.quarterLabel) · Local preference only; this does not change the GST portal"
        renderPreference()
        renderChecklist(period)
        periodMenu.isEnabled = !isWorking
    }

    private func renderChecklist(_ period: GstDashboardPeriod) {
        checklistStack.arrangedSubviews.forEach { view in
            checklistStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for item in period.checklist {
            let row = NSBox()
            row.boxType = .custom
            row.borderColor = .separatorColor
            row.borderWidth = 1
            row.cornerRadius = 6
            row.fillColor = .controlBackgroundColor

            let content = NSStackView()
            content.orientation = .horizontal
            content.alignment = .centerY
            content.spacing = 10
            content.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
                content.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
                content.topAnchor.constraint(equalTo: row.topAnchor, constant: 9),
                content.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -9)
            ])

            let indicator = NSTextField(labelWithString: checklistIndicator(item.status))
            indicator.font = .systemFont(ofSize: 17, weight: .semibold)
            indicator.textColor = checklistColor(item.status)
            indicator.alignment = .center
            indicator.widthAnchor.constraint(equalToConstant: 22).isActive = true
            content.addArrangedSubview(indicator)

            let labels = NSStackView()
            labels.orientation = .vertical
            labels.alignment = .leading
            labels.spacing = 3
            let title = NSTextField(wrappingLabelWithString: item.title)
            title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            labels.addArrangedSubview(title)
            let detail = NSTextField(wrappingLabelWithString: checklistDetail(item, period: period))
            detail.textColor = .secondaryLabelColor
            detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            labels.addArrangedSubview(detail)
            labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
            content.addArrangedSubview(labels)

            let actionSpacer = NSView()
            actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            actionSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            content.addArrangedSubview(actionSpacer)

            let button = GstChecklistActionButton(title: checklistButtonTitle(item), target: self, action: #selector(performChecklistAction(_:)))
            button.checklistAction = item.action
            button.isEnabled = checklistActionEnabled(item, period: period)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
            content.addArrangedSubview(button)

            if item.id == "generate" && item.action == "viewJson" && period.kind == "iff" && period.canGenerate {
                let regenerateButton = GstChecklistActionButton(title: "Regenerate IFF", target: self, action: #selector(performChecklistAction(_:)))
                regenerateButton.checklistAction = "generate"
                regenerateButton.isEnabled = !isWorking
                regenerateButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
                content.addArrangedSubview(regenerateButton)
            }

            checklistStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: checklistStack.widthAnchor).isActive = true
        }
    }

    private func checklistDetail(_ item: GstChecklistItem, period: GstDashboardPeriod) -> String {
        let due = item.dueDate.map { "Due \(displayDate($0))" }
        switch item.id {
        case "imsImport":
            var parts: [String] = []
            if item.status == "attention" {
                parts.append("Refresh now: the saved snapshot was imported before this check date")
            }
            if let portalCount = item.portalInvoiceCount {
                parts.append(contentsOf: [
                    "\(portalCount) IMS invoices",
                    "\(item.matchedCount ?? 0) matched existing bills",
                    "\(item.importedCount ?? 0) added"
                ])
                if (item.acceptedCount ?? 0) > 0 { parts.append("\(item.acceptedCount ?? 0) accepted") }
                if (item.pendingCount ?? 0) > 0 { parts.append("\(item.pendingCount ?? 0) pending") }
                if (item.rejectedCount ?? 0) > 0 { parts.append("\(item.rejectedCount ?? 0) rejected") }
                if (item.noActionCount ?? 0) > 0 { parts.append("\(item.noActionCount ?? 0) No Action") }
            } else {
                parts.append("Download the IMS B2B CSV from the GST portal")
            }
            if let recommendedDate = item.recommendedDate {
                parts.append("Refresh after \(displayDate(recommendedDate))")
            }
            return parts.joined(separator: " · ")
        case "gstr2bImport":
            if let portalCount = item.portalInvoiceCount {
                return [
                    "\(portalCount) portal",
                    "\(item.matchedCount ?? 0) matched",
                    "\(item.importedCount ?? 0) added",
                    "\(item.ambiguousCount ?? 0) ambiguous",
                    "\(item.missingLocalCount ?? 0) local missing",
                    "Confirmed ITC (GSTR-2B) \(money(item.effectiveInputGst ?? 0))"
                ].joined(separator: " · ")
            }
            let available = item.availableDate.map { "Available \(displayDate($0))" }
            return [available, "Download JSON/XLSX from GST portal"].compactMap { $0 }.joined(separator: " · ")
        case "input":
            let invoiceCount = item.invoiceCount ?? 0
            let foundCount = item.foundCount ?? 0
            let awaitingCount = item.missingCount ?? 0
            let currentMissingCount = max(invoiceCount - foundCount, 0)
            let carriedForwardCount = max(awaitingCount - currentMissingCount, 0)
            let periodScope = period.kind == "quarterlyGstr1" ? "quarter" : (period.month.split(separator: " ").first.map(String.init) ?? period.month)
            var parts = [
                "\(invoiceCount) \(periodScope) bills",
                "Input GST \(money(item.gstAmount ?? 0))",
                "\(awaitingCount) awaiting GSTR-2B"
            ]
            if carriedForwardCount > 0 { parts.append("\(carriedForwardCount) carried forward") }
            parts.append("Confirmed ITC \(money(item.effectiveInputGst ?? 0))")
            return parts.joined(separator: " · ")
        case "generate":
            let count = item.invoiceCount ?? 0
            return ["\(count) \(count == 1 ? "invoice" : "invoices") · Taxable \(money(item.taxableValue ?? 0)) · GST \(money(item.gstAmount ?? 0))", due].compactMap { $0 }.joined(separator: " · ")
        case "file":
            let state: String
            if let completedAt = item.completedAt {
                state = "Filed \(displayTimestamp(completedAt))"
            } else if let generatedAt = item.generatedAt {
                state = "JSON generated \(displayTimestamp(generatedAt))"
            } else {
                state = "Generate the JSON first"
            }
            return [state, due].compactMap { $0 }.joined(separator: " · ")
        case "paymentReview", "payment", "gstr3bReview", "gstr3b":
            let balance = item.estimatedBalance ?? 0
            let estimate = balance >= 0 ? "Estimated payable \(money(balance))" : "Estimated excess input credit \(money(abs(balance)))"
            let summary = "\(estimate) · Output GST \(money(item.gstAmount ?? 0)) · Confirmed ITC (GSTR-2B) \(money(item.effectiveInputGst ?? 0))"
            if let completedAt = item.completedAt {
                return "Completed \(displayTimestamp(completedAt)) · \(summary)"
            }
            return [summary, due].compactMap { $0 }.joined(separator: " · ")
        default:
            return due ?? ""
        }
    }

    private func checklistIndicator(_ status: String) -> String {
        switch status {
        case "complete": return "✓"
        case "attention": return "!"
        case "ready": return "→"
        default: return "○"
        }
    }

    private func checklistColor(_ status: String) -> NSColor {
        switch status {
        case "complete": return .systemGreen
        case "attention": return .systemOrange
        case "ready": return .controlAccentColor
        default: return .tertiaryLabelColor
        }
    }

    private func checklistButtonTitle(_ item: GstChecklistItem) -> String {
        switch item.action {
        case "manageBills": return "Manage Bills"
        case "importIms": return "Import IMS CSV"
        case "viewIms": return "Review IMS"
        case "importGstr2b": return "Import GSTR-2B"
        case "viewGstr2b": return "Review Results"
        case "generate": return "Generate"
        case "viewJson": return "View JSON"
        case "markFiled": return item.status == "complete" ? "Filed" : "Mark Filed"
        case "markPmt06Reviewed", "markGstr3bReviewed": return item.status == "complete" ? "Reviewed" : "Mark Reviewed"
        case "markPmt06Paid": return item.status == "complete" ? "Paid" : "Mark Paid"
        case "markGstr3bFiled": return item.status == "complete" ? "Filed" : "Mark Filed"
        default: return "Done"
        }
    }

    private func checklistActionEnabled(_ item: GstChecklistItem, period: GstDashboardPeriod) -> Bool {
        guard !isWorking else { return false }
        switch item.action {
        case "manageBills": return true
        case "importIms": return item.status == "ready" || item.status == "attention"
        case "viewIms": return true
        case "importGstr2b": return item.status == "ready"
        case "viewGstr2b": return true
        case "generate": return period.canGenerate
        case "viewJson": return period.outputPath.map { FileManager.default.fileExists(atPath: $0) } == true
        case "markFiled": return item.status != "complete" && period.status == "generated"
        case "markPmt06Reviewed", "markGstr3bReviewed": return item.status != "complete" && item.status == "ready"
        case "markPmt06Paid": return item.status != "complete" && item.status == "ready"
        case "markGstr3bFiled": return item.status != "complete" && item.status == "ready"
        default: return false
        }
    }

    private func renderPreference() {
        guard let preference = selectedPreference else {
            filingSchemeMenu.isEnabled = false
            iffCheckbox.isEnabled = false
            savePreferenceButton.isEnabled = false
            preferenceNoteLabel.stringValue = ""
            return
        }

        filingSchemeMenu.selectItem(at: preference.scheme == "qrmp" ? 1 : 0)
        iffCheckbox.state = preference.iffEnabled ? .on : .off
        let editable = !isWorking && !preference.locked
        filingSchemeMenu.isEnabled = editable
        iffCheckbox.isEnabled = editable && preference.scheme == "qrmp"
        savePreferenceButton.isEnabled = editable
        if preference.locked {
            preferenceNoteLabel.stringValue = "Preference locked: \(preference.lockReason ?? "GST filing activity already exists for this quarter")."
        } else {
            preferenceNoteLabel.stringValue = "Later quarters inherit this preference until you save a different one."
        }
    }

    private func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_IN")
        formatter.currencyCode = "INR"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "₹%.2f", value)
    }

    private func displayDate(_ isoDate: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: isoDate) else { return isoDate }
        let output = DateFormatter()
        output.locale = Locale(identifier: "en_IN")
        output.dateFormat = "d MMM yyyy"
        return output.string(from: date)
    }

    private func displayTimestamp(_ isoTimestamp: String) -> String {
        let input = ISO8601DateFormatter()
        guard let date = input.date(from: isoTimestamp) else { return isoTimestamp }
        let output = DateFormatter()
        output.locale = Locale(identifier: "en_IN")
        output.dateFormat = "d MMM yyyy, h:mm a"
        return output.string(from: date)
    }

    private func setActionsEnabled(_ enabled: Bool) {
        periodMenu.isEnabled = enabled
        filingSchemeMenu.isEnabled = enabled
        iffCheckbox.isEnabled = enabled
        savePreferenceButton.isEnabled = enabled
    }

    @objc private func periodChanged() {
        selectedMonth = selectedPeriod?.month
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.stringValue = ""
        render()
    }

    @objc private func performChecklistAction(_ sender: GstChecklistActionButton) {
        switch sender.checklistAction {
        case "manageBills":
            manageBillsForSelectedPeriod()
        case "importIms":
            importImsForSelectedPeriod()
        case "viewIms":
            viewImsForSelectedPeriod()
        case "importGstr2b":
            importGstr2bForSelectedPeriod()
        case "viewGstr2b":
            viewGstr2bForSelectedPeriod()
        case "generate":
            generateSelected()
        case "viewJson":
            viewSelected()
        case "markFiled":
            markSelectedFiled()
        case "markPmt06Reviewed":
            confirmManualChecklistTask(
                command: "mark-pmt06-reviewed",
                title: "Mark the monthly GST liability as reviewed?",
                explanation: "Confirm that you reviewed the portal liability and generated the PMT-06 challan. This confirmation is stored locally.",
                success: "PMT-06 liability review completed"
            )
        case "markPmt06Paid":
            confirmManualChecklistTask(
                command: "mark-pmt06-paid",
                title: "Mark \(selectedPeriod?.month ?? "this period") PMT-06 as paid?",
                explanation: "Do this only after payment succeeds on the GST portal. This records the confirmation locally.",
                success: "PMT-06 marked paid"
            )
        case "markGstr3bReviewed":
            confirmManualChecklistTask(
                command: "mark-gstr3b-reviewed",
                title: "Mark the final GSTR-3B balance as reviewed?",
                explanation: "Confirm that you checked GSTR-2B/input credit, portal liability, ledger balances and adjustments. This confirmation is stored locally.",
                success: "GSTR-3B balance review completed"
            )
        case "markGstr3bFiled":
            confirmManualChecklistTask(
                command: "mark-gstr3b-filed",
                title: "Mark GSTR-3B as filed?",
                explanation: "Do this only after the GST portal confirms filing. This records the confirmation locally.",
                success: "GSTR-3B marked filed"
            )
        default:
            break
        }
    }

    private func manageBillsForSelectedPeriod() {
        guard let period = selectedPeriod else { return }
        if period.kind != "quarterlyGstr1" {
            openBills(month: period.month)
            return
        }

        let months = selectedInputMonths.map(\.month)
        guard !months.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Choose a month to manage"
        alert.informativeText = "GSTR-2B reconciliation covers the full quarter. Update each month's purchase bills here."
        alert.addButton(withTitle: "Manage Bills")
        alert.addButton(withTitle: "Cancel")
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        picker.addItems(withTitles: months)
        picker.selectItem(withTitle: period.month)
        alert.accessoryView = picker
        guard alert.runModal() == .alertFirstButtonReturn, let month = picker.titleOfSelectedItem else { return }
        openBills(month: month)
    }

    private func openBills(month: String) {
        if billsWindow == nil {
            billsWindow = GstBillsWindowController(monthLabel: month)
            billsWindow?.onChange = { [weak self] in
                self?.reload()
            }
        } else {
            billsWindow?.setMonth(month)
        }
        billsWindow?.showWindow(nil)
        billsWindow?.window?.center()
        billsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func importImsForSelectedPeriod() {
        guard let period = selectedPeriod else { return }
        let panel = NSOpenPanel()
        panel.title = "Import GST portal IMS B2B CSV for \(period.month)"
        panel.prompt = "Import and Reconcile"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "csv")].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isWorking = true
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.stringValue = "Importing and reconciling IMS records…"
        render()
        Task.detached {
            do {
                let imported = try TimeLogClient().importIms(period: period.month, path: url.path)
                await MainActor.run {
                    self.isWorking = false
                    self.showImsResults(imported)
                    self.reload()
                    self.messageLabel.textColor = .secondaryLabelColor
                    self.messageLabel.stringValue = "IMS CSV imported and reconciled"
                }
            } catch {
                await MainActor.run {
                    self.isWorking = false
                    self.messageLabel.textColor = .systemRed
                    self.messageLabel.stringValue = error.localizedDescription
                    self.render()
                }
            }
        }
    }

    private func viewImsForSelectedPeriod() {
        guard let period = selectedPeriod else { return }
        do {
            showImsResults(try client.imsImport(period: period.month))
        } catch {
            messageLabel.textColor = .systemRed
            messageLabel.stringValue = error.localizedDescription
        }
    }

    private func showImsResults(_ data: ImsImportData) {
        let controller = ImsResultsWindowController(
            data: data,
            onManageBills: { [weak self] in self?.manageBillsForSelectedPeriod() },
            onImportAgain: { [weak self] in self?.importImsForSelectedPeriod() }
        )
        imsResultsWindow = controller
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func importGstr2bForSelectedPeriod() {
        guard let period = selectedPeriod else { return }
        let panel = NSOpenPanel()
        let filingLabel = period.kind == "quarterlyGstr1" ? period.quarterLabel : period.month
        panel.title = "Import \(filingLabel) GSTR-2B"
        panel.prompt = "Import and Reconcile"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["json", "xlsx"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isWorking = true
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.stringValue = "Importing and reconciling GSTR-2B…"
        render()
        Task.detached {
            do {
                let imported = try TimeLogClient().importGstr2b(period: period.month, path: url.path)
                await MainActor.run {
                    self.isWorking = false
                    self.showGstr2bResults(imported, period: period)
                    self.reload()
                    self.messageLabel.textColor = .secondaryLabelColor
                    self.messageLabel.stringValue = "GSTR-2B imported and reconciled"
                }
            } catch {
                await MainActor.run {
                    self.isWorking = false
                    self.messageLabel.textColor = .systemRed
                    self.messageLabel.stringValue = error.localizedDescription
                    self.render()
                }
            }
        }
    }

    private func viewGstr2bForSelectedPeriod() {
        guard let period = selectedPeriod else { return }
        do {
            showGstr2bResults(try client.gstr2bImport(period: period.month), period: period)
        } catch {
            messageLabel.textColor = .systemRed
            messageLabel.stringValue = error.localizedDescription
        }
    }

    private func showGstr2bResults(_ data: Gstr2bImportData, period: GstDashboardPeriod) {
        let controller = Gstr2bResultsWindowController(data: data) { [weak self] in
            self?.manageBillsForSelectedPeriod()
        }
        gstr2bResultsWindow = controller
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func confirmManualChecklistTask(command: String, title: String, explanation: String, success: String) {
        guard let period = selectedPeriod else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = explanation
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Confirm")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform(command: command, period: period, success: success)
    }

    @objc private func preferenceSchemeChanged() {
        let qrmp = filingSchemeMenu.indexOfSelectedItem == 1
        if !qrmp {
            iffCheckbox.state = .off
        }
        iffCheckbox.isEnabled = qrmp && selectedPreference?.locked == false && !isWorking
    }

    @objc private func preferenceIffChanged() {
        // The value is persisted only when Save Preference is clicked.
    }

    @objc private func savePreference() {
        guard let preference = selectedPreference, !preference.locked, !isWorking else { return }
        let scheme = filingSchemeMenu.indexOfSelectedItem == 1 ? "qrmp" : "monthly"
        let iff = scheme == "qrmp" && iffCheckbox.state == .on ? "enabled" : "disabled"
        isWorking = true
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.stringValue = "Saving filing preference…"
        render()

        Task.detached {
            do {
                _ = try TimeLogClient().run("set-gst-preference", [preference.quarterStartMonth, scheme, iff])
                await MainActor.run {
                    self.isWorking = false
                    self.reload()
                    self.messageLabel.textColor = .secondaryLabelColor
                    self.messageLabel.stringValue = "Filing preference saved"
                }
            } catch {
                await MainActor.run {
                    self.isWorking = false
                    self.messageLabel.textColor = .systemRed
                    self.messageLabel.stringValue = error.localizedDescription
                    self.render()
                }
            }
        }
    }

    @objc private func refreshClicked() {
        reload()
    }

    @objc private func generateSelected() {
        guard let period = selectedPeriod, period.canGenerate else { return }
        if period.kind == "iff" && period.status == "generated" {
            let alert = NSAlert()
            alert.messageText = "Regenerate \(period.month) IFF JSON?"
            alert.informativeText = "This replaces the existing JSON using the current invoice data. The IFF will remain unfiled until you confirm filing separately."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Regenerate IFF")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let command = period.kind == "iff" ? "generate-iff" : "generate-gst"
        perform(command: command, period: period, success: "\(period.actionTitle) JSON generated")
    }

    @objc private func viewSelected() {
        guard let path = selectedPeriod?.outputPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func markSelectedFiled() {
        guard let period = selectedPeriod, period.status == "generated" else { return }
        let alert = NSAlert()
        alert.messageText = "Mark \(period.month) \(period.actionTitle) as filed?"
        alert.informativeText = "Do this only after the GST portal confirms filing. This period and its invoice GST data will become read-only."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Mark Filed")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let command = period.kind == "iff" ? "mark-iff-filed" : "mark-gstr1-filed"
        perform(command: command, period: period, success: "\(period.actionTitle) marked filed")
    }

    private func perform(command: String, period: GstDashboardPeriod, success: String) {
        guard !isWorking else { return }
        isWorking = true
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.stringValue = "Working…"
        render()

        Task.detached {
            do {
                _ = try TimeLogClient().run(command, [period.month])
                await MainActor.run {
                    self.isWorking = false
                    self.selectedMonth = period.month
                    self.reload()
                    self.messageLabel.textColor = .secondaryLabelColor
                    self.messageLabel.stringValue = success
                }
            } catch {
                await MainActor.run {
                    self.isWorking = false
                    self.messageLabel.textColor = .systemRed
                    self.messageLabel.stringValue = error.localizedDescription
                    self.render()
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let client = TimeLogClient()
    private var status: TimeLogStatus?
    private var statusFetchedAt = Date()
    private var lastError: String?
    private var generationKind: String?
    private var isGenerating: Bool { generationKind != nil }
    private var generationStartedAt: Date?
    private var displayTimer: DispatchSourceTimer?
    private var activity: NSObjectProtocol?
    private var statusRefreshTicks = 0
    private var statusPollInFlight = false
    private var dailyHoursWindow: DailyHoursWindowController?
    private var gstDashboardWindow: GstDashboardWindowController?
    private var lastDailyTargetNotificationDate: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSUserNotificationCenter.default.delegate = self
        configureApplicationMenu()
        configureStatusItem()
        refresh(command: "status")
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        displayTimer = timer
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        appMenu.addItem(NSMenuItem(title: "Quit InvoiceTimer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        NSApp.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        statusItem.button?.title = "00:00"
        rebuildMenu()
    }

    private func refresh(command: String, notifyOnError: Bool = false) {
        do {
            status = try client.run(command)
            statusFetchedAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            if notifyOnError {
                notifyActionFailure(command: command, error: error)
            }
        }

        updateTitle()
        updateActivity()
        rebuildMenu()
    }

    private func applyStatus(_ nextStatus: TimeLogStatus) {
        let previousStatus = status
        status = nextStatus
        statusFetchedAt = Date()
        lastError = nil
        updateTitle()
        maybeNotifyDailyTarget(previousStatus: previousStatus, currentStatus: nextStatus)
        updateActivity()
        rebuildMenu()
    }

    private func currentElapsedSeconds() -> Double {
        guard let status else { return 0 }
        if status.status == "running" {
            return status.elapsedSeconds + Date().timeIntervalSince(statusFetchedAt)
        }

        return status.elapsedSeconds
    }

    private func updateTitle() {
        let seconds = currentElapsedSeconds()
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        // Keep the status item narrow. macOS hides status items when the menu bar
        // runs out of room, and appending a project label can make the timer vanish.
        let title = String(format: "%02d:%02d:%02d", hours, minutes, Int(seconds) % 60)
        let baseTitle = isGenerating ? "↻ \(title)" : title
        statusItem.button?.attributedTitle = NSAttributedString(
            string: baseTitle,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    private func tick() {
        if status?.status == "running" {
            updateTitle()
            pollStatusFromRuby()
        } else {
            statusRefreshTicks += 1
            updateTitle()

            if statusRefreshTicks >= 30 {
                statusRefreshTicks = 0
                refresh(command: "status")
            }
        }
    }

    private func pollStatusFromRuby() {
        guard !statusPollInFlight else { return }
        statusPollInFlight = true

        Task.detached {
            do {
                let nextStatus = try TimeLogClient().run("status")
                await MainActor.run {
                    self.statusPollInFlight = false
                    self.applyStatus(nextStatus)
                    self.statusItem.button?.needsDisplay = true
                }
            } catch {
                await MainActor.run {
                    self.statusPollInFlight = false
                    self.lastError = error.localizedDescription
                    self.updateTitle()
                }
            }
        }
    }

    private func updateActivity() {
        let shouldStayActive = status?.status == "running" || isGenerating
        if shouldStayActive && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "InvoiceTimer is tracking active work time"
            )
        } else if !shouldStayActive, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private var hasProject: Bool {
        guard let status else { return false }
        return !status.projects.isEmpty && status.status != "unconfigured"
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        // Session actions manage their own enabled state. AppKit's automatic
        // action validation would otherwise re-enable Finish and Discard
        // whenever their selectors exist on the target.
        menu.autoenablesItems = false

        if let status, hasProject {
            menu.addItem(disabledItem("Project: \(status.projectLabel)"))
            menu.addItem(disabledItem("Workday: \(formatWorkday(status.workday)) · \(formatHours(status.todayHours))"))
            menu.addItem(disabledItem(dailyTargetSummary(status)))
            menu.addItem(.separator())
            menu.addItem(disabledItem("Month: \(status.month)"))
            menu.addItem(disabledItem("Timer: \(formatHours(status.monthlyActualHours))"))
            menu.addItem(disabledItem("Billed: \(formatHours(status.monthlyBilledHours))"))
            menu.addItem(disabledItem("Avg/day: \(formatHours(status.averageHoursPerWorkingDay))"))
            menu.addItem(disabledItem(targetSummary(status)))
        } else {
            menu.addItem(disabledItem("Add a project to start tracking time"))
        }

        if let lastError, !lastError.isEmpty {
            menu.addItem(disabledItem("Error: \(shortError(lastError))"))
        }

        menu.addItem(.separator())

        switch status?.status {
        case "running":
            menu.addItem(actionItem("Pause", action: #selector(pause)))
        case "paused":
            menu.addItem(actionItem("Resume", action: #selector(start)))
        default:
            let start = actionItem("Start", action: #selector(start))
            start.isEnabled = hasProject
            menu.addItem(start)
        }

        let canFinish = status?.status == "running" || status?.status == "paused"
        let finish = actionItem("Finish", action: #selector(finish))
        finish.isEnabled = canFinish
        menu.addItem(finish)

        let discard = actionItem("Discard", action: #selector(discard))
        discard.isEnabled = canFinish
        menu.addItem(discard)

        menu.addItem(.separator())
        menu.addItem(generateInvoiceMenuItem())
        menu.addItem(gstDashboardMenuItem())
        menu.addItem(editMenuItem())
        menu.addItem(reimbursementsMenuItem())
        menu.addItem(actionItem("Refresh", action: #selector(refreshStatus)))
        menu.addItem(projectsMenuItem())
        let openInvoiceFolder = actionItem("Open Invoice Folder", action: #selector(openInvoiceFolder))
        openInvoiceFolder.isEnabled = hasProject
        menu.addItem(openInvoiceFolder)
        let openConfig = actionItem("Open Config JSON", action: #selector(openConfigJSON))
        openConfig.isEnabled = hasProject
        menu.addItem(openConfig)
        menu.addItem(actionItem("Open Error Log", action: #selector(openErrorLog)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit", action: #selector(quit)))

        statusItem.menu = menu
    }

    private func generateInvoiceMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: generationKind == "invoice" ? "Generating Invoice..." : "Generate Invoice", action: nil, keyEquivalent: "")
        item.isEnabled = hasProject && !isGenerating

        let submenu = NSMenu()
        let currentMonth = status?.currentMonth ?? status?.month ?? "Current Month"
        let previousMonth = status?.previousMonth ?? "Previous Month"

        let current = NSMenuItem(title: "Current Month (\(currentMonth))", action: #selector(generateInvoiceForMonth(_:)), keyEquivalent: "")
        current.target = self
        current.representedObject = currentMonth
        current.isEnabled = hasProject && !isGenerating
        submenu.addItem(current)

        let previous = NSMenuItem(title: "Previous Month (\(previousMonth))", action: #selector(generateInvoiceForMonth(_:)), keyEquivalent: "")
        previous.target = self
        previous.representedObject = previousMonth
        previous.isEnabled = hasProject && !isGenerating
        submenu.addItem(previous)

        let custom = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
        custom.isEnabled = false
        submenu.addItem(custom)

        item.submenu = submenu
        return item
    }

    private func gstDashboardMenuItem() -> NSMenuItem {
        let item = actionItem("Open GST Dashboard", action: #selector(openGstDashboard))
        item.isEnabled = hasProject && !isGenerating
        return item
    }

    private func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.isEnabled = hasProject
        let submenu = NSMenu()
        let currentMonth = status?.currentMonth ?? status?.month ?? "Current Month"
        let previousMonth = status?.previousMonth ?? "Previous Month"

        let current = NSMenuItem(title: "Current Month (\(currentMonth))", action: #selector(editDailyHoursForMonth(_:)), keyEquivalent: "")
        current.target = self
        current.representedObject = currentMonth
        current.isEnabled = hasProject
        submenu.addItem(current)

        let previous = NSMenuItem(title: "Previous Month (\(previousMonth))", action: #selector(editDailyHoursForMonth(_:)), keyEquivalent: "")
        previous.target = self
        previous.representedObject = previousMonth
        previous.isEnabled = hasProject
        submenu.addItem(previous)

        let custom = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
        custom.isEnabled = false
        submenu.addItem(custom)

        item.submenu = submenu
        return item
    }

    private func reimbursementsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Reimbursements", action: nil, keyEquivalent: "")
        item.isEnabled = hasProject
        let submenu = NSMenu()
        guard let status, hasProject else {
            item.submenu = submenu
            return item
        }

        submenu.addItem(reimbursementMonthItem(
            title: "Current Month (\(status.currentMonth))",
            month: status.currentMonth,
            entries: status.currentReimbursements
        ))
        submenu.addItem(reimbursementMonthItem(
            title: "Previous Month (\(status.previousMonth))",
            month: status.previousMonth,
            entries: status.previousReimbursements
        ))
        item.submenu = submenu
        return item
    }

    private func reimbursementMonthItem(title: String, month: String, entries: [ReimbursementEntry]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let add = actionItem("Add Reimbursement…", action: #selector(addReimbursement(_:)))
        add.representedObject = ReimbursementReference(month: month)
        submenu.addItem(add)
        submenu.addItem(.separator())

        if entries.isEmpty {
            submenu.addItem(disabledItem("No reimbursements"))
        } else {
            for entry in entries {
                let attachment = entry.attachment == nil ? "" : "  📎"
                let entryItem = actionItem(
                    String(format: "%@ — ₹%.2f%@", entry.name, entry.amount, attachment),
                    action: #selector(removeReimbursement(_:))
                )
                entryItem.representedObject = ReimbursementReference(month: month, id: entry.id, name: entry.name)
                submenu.addItem(entryItem)
            }
        }

        item.submenu = submenu
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func shortError(_ message: String) -> String {
        let firstLine = message
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "See error log"
        guard firstLine.count > 80 else { return firstLine }

        let end = firstLine.index(firstLine.startIndex, offsetBy: 77)
        return "\(firstLine[..<end])..."
    }

    private func notifyActionFailure(command: String, error: Error) {
        notify(
            title: "\(actionName(command)) failed",
            body: shortError(error.localizedDescription),
            destination: "errorLog",
            path: TimeLogClient.errorLogURL.path
        )
    }

    private func actionName(_ command: String) -> String {
        switch command {
        case "start":
            return status?.status == "paused" ? "Resume" : "Start"
        case "pause":
            return "Pause"
        case "finish":
            return "Finish"
        case "discard":
            return "Discard"
        default:
            return command
        }
    }

    private func projectsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Project", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        if let status {
            for project in status.projects {
                let projectItem = NSMenuItem(title: project.label, action: #selector(switchProject(_:)), keyEquivalent: "")
                projectItem.target = self
                projectItem.representedObject = project.label
                projectItem.state = project.active ? .on : .off
                submenu.addItem(projectItem)
            }
        }

        if submenu.items.isEmpty {
            submenu.addItem(disabledItem("No projects configured"))
        }

        submenu.addItem(.separator())
        submenu.addItem(actionItem("Add Project", action: #selector(addProjectConfig)))

        item.submenu = submenu
        return item
    }

    private func formatHours(_ value: Double) -> String {
        String(format: "%.2fh", value)
    }

    private func targetSummary(_ status: TimeLogStatus) -> String {
        guard status.targetHours > 0 else { return "Target: not set" }

        if status.targetRemainingHours >= 0 {
            return "Target left: \(formatHours(status.targetRemainingHours)) (~\(status.daysToTarget)d)"
        }

        return "Over target: \(formatHours(abs(status.targetRemainingHours)))"
    }

    private func dailyTargetSummary(_ status: TimeLogStatus) -> String {
        if status.dailyTargetRemainingHours > 0 {
            if let finishAt = formatFinishTime(status.dailyTargetFinishAt), status.status == "running" {
                return "Remaining: \(formatHours(status.dailyTargetRemainingHours)) (free \(finishAt))"
            }

            return "Remaining: \(formatHours(status.dailyTargetRemainingHours))"
        }

        return "Overtime: \(formatHours(status.dailyOvertimeHours))"
    }

    private func formatWorkday(_ isoDate: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: isoDate) else { return isoDate }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func formatFinishTime(_ isoString: String?) -> String? {
        guard let isoString else { return nil }
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: isoString) else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func maybeNotifyDailyTarget(previousStatus: TimeLogStatus?, currentStatus: TimeLogStatus) {
        guard currentStatus.dailyTargetAchieved,
              currentStatus.status == "running",
              lastDailyTargetNotificationDate != currentStatus.workday else {
            return
        }

        if previousStatus?.dailyTargetAchieved == true && previousStatus?.workday == currentStatus.workday {
            return
        }

        lastDailyTargetNotificationDate = currentStatus.workday
        notify(title: "Daily target achieved", body: "\(currentStatus.projectLabel) \(formatHours(currentStatus.todayHours)) logged for \(formatWorkday(currentStatus.workday))")
    }

    @objc private func refreshStatus() {
        refresh(command: "status", notifyOnError: true)
    }

    @objc private func switchProject(_ sender: NSMenuItem) {
        guard let label = sender.representedObject as? String else { return }
        do {
            status = try client.run("switch-project", [label])
            statusFetchedAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            notify(
                title: "Switch Project failed",
                body: shortError(error.localizedDescription),
                destination: "errorLog",
                path: TimeLogClient.errorLogURL.path
            )
        }

        updateTitle()
        rebuildMenu()
    }

    @objc private func addProjectConfig() {
        let alert = NSAlert()
        alert.messageText = "Project Label"
        alert.informativeText = "Enter the short label to show in the timer menu."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "NEW"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let label = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.title = "Select Project Config"
        panel.message = "Choose the existing config.json for \(label). Its outputDir controls where invoice-month folders and time logs are stored."
        panel.prompt = "Add Project"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let configURL = panel.url else { return }

        do {
            status = try client.run("add-project", [label, configURL.path])
            statusFetchedAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            notify(
                title: "Add Project failed",
                body: shortError(error.localizedDescription),
                destination: "errorLog",
                path: TimeLogClient.errorLogURL.path
            )
        }

        updateTitle()
        rebuildMenu()
    }

    @objc private func start() {
        refresh(command: "start", notifyOnError: true)
    }

    @objc private func pause() {
        refresh(command: "pause", notifyOnError: true)
    }

    @objc private func finish() {
        refresh(command: "finish", notifyOnError: true)
    }

    @objc private func discard() {
        refresh(command: "discard", notifyOnError: true)
    }

    @objc private func addReimbursement(_ sender: NSMenuItem) {
        guard let reference = sender.representedObject as? ReimbursementReference else { return }
        let nameField = NSTextField(frame: NSRect(x: 0, y: 38, width: 280, height: 24))
        nameField.placeholderString = "Name"
        let amountField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        amountField.placeholderString = "Amount in INR"
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 62))
        accessory.addSubview(nameField)
        accessory.addSubview(amountField)
        var attachmentURL: URL?

        while true {
            let alert = NSAlert()
            alert.messageText = "Add Reimbursement · \(reference.month)"
            alert.informativeText = attachmentURL.map { "Attachment: \($0.lastPathComponent)" } ?? "Attachment is optional."
            alert.accessoryView = accessory
            alert.addButton(withTitle: "Add")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: attachmentURL == nil ? "Choose Attachment…" : "Change Attachment…")
            let response = alert.runModal()
            if response == .alertSecondButtonReturn { return }
            if response == .alertThirdButtonReturn {
                let panel = NSOpenPanel()
                panel.title = "Choose Reimbursement Attachment"
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK {
                    attachmentURL = panel.url
                }
                continue
            }

            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = amountField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, Double(amount).map({ $0 > 0 }) == true else {
                let validation = NSAlert()
                validation.messageText = "Enter a name and a positive amount."
                validation.runModal()
                continue
            }

            do {
                var arguments = [reference.month, name, amount]
                if let attachmentURL { arguments.append(attachmentURL.path) }
                applyStatus(try client.run("add-reimbursement", arguments))
            } catch {
                lastError = error.localizedDescription
                rebuildMenu()
                notifyActionFailure(command: "Add reimbursement", error: error)
            }
            return
        }
    }

    @objc private func removeReimbursement(_ sender: NSMenuItem) {
        guard let reference = sender.representedObject as? ReimbursementReference,
              let id = reference.id else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \(reference.name ?? "reimbursement")?"
        alert.informativeText = "The entry and its copied attachment, if any, will be removed."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            applyStatus(try client.run("remove-reimbursement", [reference.month, id]))
        } catch {
            lastError = error.localizedDescription
            rebuildMenu()
            notifyActionFailure(command: "Remove reimbursement", error: error)
        }
    }

    @objc private func generateInvoiceForMonth(_ sender: NSMenuItem) {
        generateInvoice(month: sender.representedObject as? String)
    }

    private func generateInvoice(month: String? = nil) {
        guard !isGenerating else { return }
        generationKind = "invoice"
        generationStartedAt = Date()
        updateTitle()
        rebuildMenu()

        Task.detached {
            do {
                let client = TimeLogClient()
                let arguments = month.map { [$0] } ?? []
                let result = try client.run("generate", arguments)
                await MainActor.run {
                    self.status = result
                    self.statusFetchedAt = Date()
                    self.lastError = nil
                    self.generationKind = nil
                    self.updateTitle()
                    self.updateActivity()
                    self.rebuildMenu()
                    self.notify(
                        title: "Invoice generated",
                        body: "\(result.projectLabel) \(result.month)",
                        destination: "folder",
                        path: result.outputDir
                    )
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.generationKind = nil
                    self.updateTitle()
                    self.updateActivity()
                    self.rebuildMenu()
                    self.notify(
                        title: "Invoice generation failed",
                        body: self.shortError(error.localizedDescription),
                        destination: "errorLog",
                        path: TimeLogClient.errorLogURL.path
                    )
                }
            }
        }
    }

    @objc private func openGstDashboard() {
        if gstDashboardWindow == nil {
            gstDashboardWindow = GstDashboardWindowController()
        } else {
            gstDashboardWindow?.refresh()
        }
        gstDashboardWindow?.showWindow(nil)
        gstDashboardWindow?.window?.center()
        gstDashboardWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func editDailyHoursForMonth(_ sender: NSMenuItem) {
        let month = sender.representedObject as? String ?? status?.currentMonth ?? status?.month ?? ""
        guard !month.isEmpty else { return }
        editDailyHours(month: month)
    }

    private func editDailyHours(month: String) {
        if dailyHoursWindow == nil {
            dailyHoursWindow = DailyHoursWindowController(monthLabel: month)
        } else {
            dailyHoursWindow?.setMonth(month)
        }

        dailyHoursWindow?.showWindow(nil)
        dailyHoursWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openInvoiceFolder() {
        guard let status else {
            refresh(command: "status")
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: status.outputDir))
    }

    @objc private func openConfigJSON() {
        guard let status else {
            refresh(command: "status")
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: status.projectConfigPath))
    }

    @objc private func openErrorLog() {
        TimeLogClient.ensureErrorLogFile()
        NSWorkspace.shared.open(TimeLogClient.errorLogURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func notify(title: String, body: String, destination: String? = nil, path: String? = nil) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        if let destination, let path {
            notification.userInfo = [
                "destination": destination,
                "path": path
            ]
        }
        NSUserNotificationCenter.default.deliver(notification)
    }

    private func openNotificationDestination(_ payload: [String: String]) {
        guard let path = payload["path"] else { return }

        if payload["destination"] == "errorLog" {
            TimeLogClient.ensureErrorLogFile()
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

extension AppDelegate: NSUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        shouldPresent notification: NSUserNotification
    ) -> Bool {
        true
    }

    nonisolated func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        didActivate notification: NSUserNotification
    ) {
        guard let payload = notification.userInfo as? [String: String] else { return }

        Task { @MainActor in
            self.openNotificationDestination(payload)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
