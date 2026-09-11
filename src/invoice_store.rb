require "json"
require "fileutils"
require "tempfile"
require "digest"
require_relative "invoice_calculation"

# Mutable project data lives under outputDir. Project configuration is input only.
class InvoiceStore
  METADATA_FIELDS = %w[month invoiceNo targetHours dailyTargetHours].freeze
  attr_reader :root

  def initialize(config)
    @config = config
    @root = File.expand_path(InvoiceCalculation.field(config, "outputDir", String))
  end

  def self.write_json(path, value)
    write_bytes(path, JSON.pretty_generate(value) + "\n")
  end

  def self.write_bytes(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    mode = File.exist?(path) ? File.stat(path).mode & 0777 : 0600
    temporary = Tempfile.new([".invoice-", ".tmp"], File.dirname(path))
    begin
      temporary.binmode
      temporary.write(content)
      temporary.flush
      temporary.fsync
      temporary.chmod(mode)
      temporary.close
      File.rename(temporary.path, path)
    ensure
      temporary.close!
    end
  end

  def directory(record)
    validate_record!(record)
    File.join(root, "#{record.fetch('invoiceNo')} #{record.fetch('month')}")
  end

  def records
    locked { |records, _| records.map { |record| with_reimbursements(record) } }
  end

  def find(month)
    validate_month!(month)
    records.find { |record| record["month"] == month }
  end

  def find_or_create(month)
    validate_month!(month)
    locked do |records, sequence|
      record = records.find { |item| item["month"] == month }
      unless record
        number = sequence.fetch("nextInvoiceNo")
        record = { "month" => month, "invoiceNo" => format("%03d", number) }
        # The directory reserves this allocation. If interrupted before either
        # JSON write, its name is sufficient to recover without reusing a number.
        FileUtils.mkdir_p(directory(record))
        self.class.write_json(File.join(directory(record), "reimbursements.json"), [])
        self.class.write_json(File.join(directory(record), "invoice.json"), record)
        self.class.write_json(sequence_path, sequence.merge("nextInvoiceNo" => number + 1))
      end
      with_reimbursements(record)
    end
  end

  def update_metadata(month, changes)
    unless (changes.keys - %w[targetHours dailyTargetHours]).empty?
      raise "Only monthly target overrides can be changed in invoice.json"
    end
    locked do |records, _|
      record = records.find { |item| item["month"] == month }
      raise "No invoice record for #{month}" unless record
      self.class.write_json(File.join(directory(record), "invoice.json"), record.merge(changes))
    end
  end

  def update_reimbursements(month)
    locked do |records, _|
      record = records.find { |item| item["month"] == month }
      raise "No invoice record for #{month}" unless record
      path = File.join(directory(record), "reimbursements.json")
      entries = read_reimbursements(record)
      updated = yield(entries, record)
      raise "Reimbursements must be an array" unless updated.is_a?(Array)
      self.class.write_json(path, updated)
      updated
    end
  end

  # Only this explicitly invoked migration command edits a project config.
  # Normal access imports legacy data once and leaves the config byte-for-byte intact.
  def self.migrate_config(path)
    original = File.binread(path)
    config = JSON.parse(original)
    store = new(config)
    records = store.records
    result = { "outputDir" => store.root, "invoiceCount" => records.length, "configUpdated" => false }
    return result unless config.key?("invoices")

    backup = File.join(store.root, ".migration", "config-#{Digest::SHA256.hexdigest(original)}.json")
    write_bytes(backup, original) unless File.exist?(backup)
    raise "Project config changed during migration; retry without overwriting those edits" unless File.binread(path) == original
    config.delete("invoices")
    write_json(path, config)
    result.merge("configUpdated" => true, "backupPath" => backup)
  end

  private

  def sequence_path
    File.join(root, "sequence.json")
  end

  def locked
    FileUtils.mkdir_p(root)
    # Lock a stable inode: sequence.json itself is replaced atomically.
    File.open(File.join(root, ".sequence.lock"), File::RDWR | File::CREAT, 0600) do |lock|
      lock.flock(File::LOCK_EX)
      records, sequence = prepare
      yield(records, sequence)
    ensure
      lock.flock(File::LOCK_UN) if lock
    end
  end

  def validate_month!(month)
    start = InvoiceCalculation.parse_month(month).first
    raise "Invoice month must use Month YYYY" unless start.strftime("%B %Y") == month
  end

  def validate_record!(record)
    raise "Invoice record must be an object" unless record.is_a?(Hash)
    validate_month!(record.fetch("month"))
    number = record.fetch("invoiceNo")
    unless number.is_a?(String) && number.match?(/\A[0-9]+\z/) && number.to_i.positive?
      raise "Invoice number must be a positive numeric string"
    end
  end

  def read_reimbursements(record)
    entries = JSON.parse(File.read(File.join(directory(record), "reimbursements.json")))
    raise "Reimbursements must be an array for #{record['month']}" unless entries.is_a?(Array)
    entries
  end

  def with_reimbursements(record)
    record.merge("reimbursements" => read_reimbursements(record))
  end

  def prepare
    sequence = File.file?(sequence_path) ? JSON.parse(File.read(sequence_path)) : { "nextInvoiceNo" => 1 }
    unless sequence.is_a?(Hash) && sequence["nextInvoiceNo"].is_a?(Integer) && sequence["nextInvoiceNo"].positive?
      raise "sequence.json must contain a positive integer nextInvoiceNo"
    end
    importing = sequence["legacyImported"] != true
    by_month = {}
    # Also recover directories left by an interrupted allocation, and existing
    # invoice folders whose config record is no longer available.
    Dir.children(root).sort.each do |name|
      next unless name.match?(/\A[0-9]+ [A-Za-z]+ [0-9]{4}\z/) && File.directory?(File.join(root, name))
      number, month = name.split(" ", 2)
      path = File.join(root, name, "invoice.json")
      record = File.file?(path) ? JSON.parse(File.read(path)) : { "invoiceNo" => number, "month" => month }
      validate_record!(record)
      raise "Invoice metadata does not match folder #{name}" unless File.basename(directory(record)) == name
      raise "Multiple invoice folders found for #{month}" if by_month.key?(month)
      by_month[month] = record
    end

    legacy = {}
    if importing
      entries = @config.fetch("invoices", [])
      raise "Legacy invoices must be an array" unless entries.is_a?(Array)
      entries.each do |record|
        validate_record!(record)
        month = record.fetch("month")
        raise "Duplicate legacy invoice month: #{month}" if legacy.key?(month)
        legacy[month] = record
        existing = by_month[month]
        if existing && existing["invoiceNo"] != record["invoiceNo"]
          raise "Legacy invoice number conflicts with folder for #{month}"
        end
        # Metadata already committed during a prior interrupted import wins.
        unless existing && File.file?(File.join(directory(existing), "invoice.json"))
          by_month[month] = record.select { |key, _| METADATA_FIELDS.include?(key) }
        end
      end
    end

    records = by_month.values.sort_by { |record| record.fetch("invoiceNo").to_i }
    numbers = records.map { |record| record.fetch("invoiceNo").to_i }
    raise "Duplicate invoice numbers in output directory" unless numbers.uniq == numbers
    # Check every source/destination before moving any existing files.
    moves = []
    records.each do |record|
      dir = directory(record)
      reimbursements_path = File.join(dir, "reimbursements.json")
      reimbursements = File.file?(reimbursements_path) ? JSON.parse(File.read(reimbursements_path)) : legacy.fetch(record["month"], {}).fetch("reimbursements", [])
      raise "Reimbursements must be an array for #{record['month']}" unless reimbursements.is_a?(Array)
      next unless importing
      label = record.fetch("month").tr(" ", "_")
      { "TimeLog_#{label}.json" => "timelog.json", "TimeLog_#{label}.state.json" => "timelog.state.json" }.each do |old, current|
        source, target = File.join(dir, old), File.join(dir, current)
        next unless File.file?(source)
        if File.exist?(target) && File.binread(source) != File.binread(target)
          raise "Conflicting legacy and current time logs: #{source} and #{target}"
        end
        moves << [source, target]
      end
    end
    records.each do |record|
      dir = directory(record)
      FileUtils.mkdir_p(dir)
      reimbursements_path = File.join(dir, "reimbursements.json")
      unless File.exist?(reimbursements_path)
        self.class.write_json(reimbursements_path, legacy.fetch(record["month"], {}).fetch("reimbursements", []))
      end
      invoice_path = File.join(dir, "invoice.json")
      self.class.write_json(invoice_path, record) unless File.exist?(invoice_path)
    end
    moves.each { |source, target| File.rename(source, target) }
    updated = sequence.merge("nextInvoiceNo" => [sequence.fetch("nextInvoiceNo"), (numbers.max || 0) + 1].max, "legacyImported" => true)
    self.class.write_json(sequence_path, updated) if !File.exist?(sequence_path) || updated != sequence
    [records, updated]
  end
end
