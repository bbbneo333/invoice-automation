require_relative "invoice_calculation"

# Presentation rules only: currency, tax policy and arithmetic are independent.
module DocumentLocale
  DEFAULT = "en-IN"
  PROFILES = {
    "en-IN" => { group: ",", decimal: ".", secondary_group: 2, date: "%d %b %Y", excel_date: "dd mmm yyyy" },
    "en-US" => { group: ",", decimal: ".", secondary_group: 3, date: "%b %d, %Y", excel_date: "[$-409]mmm dd, yyyy" },
    "de-DE" => { group: ".", decimal: ",", secondary_group: 3, date: "%d.%m.%Y", excel_date: "[$-407]dd.mm.yyyy" }
  }.freeze

  module_function

  def from_config(config)
    validate(config.fetch("locale", DEFAULT))
  end

  def validate(locale)
    unless PROFILES.key?(locale)
      raise InvoiceCalculation::ConfigError, "Unsupported locale #{locale.inspect}; supported locales: #{PROFILES.keys.join(', ')}"
    end
    locale
  end

  def profile(locale)
    PROFILES.fetch(validate(locale))
  end

  def money(value, locale = DEFAULT)
    rules = profile(locale)
    value = InvoiceCalculation.money(value)
    # Keep decimal digits exact; never convert money to binary Float.
    whole, fraction = value.abs.to_s("F").split(".")
    fraction = fraction.to_s.ljust(2, "0")[0, 2]
    if whole.length > 3
      head, tail = whole[0...-3], whole[-3, 3]
      groups = head.reverse.scan(/.{1,#{rules[:secondary_group]}}/).map(&:reverse).reverse
      whole = (groups + [tail]).join(rules[:group])
    end
    "#{value.negative? ? '-' : ''}#{whole}#{rules[:decimal]}#{fraction}"
  end

  def quantity(value, locale = DEFAULT)
    rules = profile(locale)
    value = InvoiceCalculation.decimal_value(value, "quantity")
    return value.to_i.to_s if value.frac.zero?
    value.to_s("F").sub(/0+\z/, "").sub(/\.\z/, "").sub(".", rules[:decimal])
  end

  def date(value, locale = DEFAULT)
    value.strftime(profile(locale).fetch(:date))
  end
end
