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
            fileManager.fileExists(atPath: $0.appendingPathComponent("time_log.rb").path)
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
        process.arguments = ["ruby", "time_log.rb", command] + arguments
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let client = TimeLogClient()
    private var status: TimeLogStatus?
    private var statusFetchedAt = Date()
    private var lastError: String?
    private var isGenerating = false
    private var generationStartedAt: Date?
    private var displayTimer: DispatchSourceTimer?
    private var activity: NSObjectProtocol?
    private var statusRefreshTicks = 0
    private var statusPollInFlight = false
    private var dailyHoursWindow: DailyHoursWindowController?
    private var lastDailyTargetNotificationDate: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSUserNotificationCenter.default.delegate = self
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
        let item = NSMenuItem(title: isGenerating ? "Generating Invoice..." : "Generate Invoice", action: nil, keyEquivalent: "")
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
        isGenerating = true
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
                    self.isGenerating = false
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
                    self.isGenerating = false
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
