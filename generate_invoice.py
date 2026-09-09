import json
import os
import shutil
import subprocess
import sys
import tempfile
from glob import glob
from datetime import date
from decimal import Decimal, ROUND_HALF_UP

BASE_DIR = os.path.dirname(__file__)
def default_registry_path():
    if sys.platform == "darwin":
        base = os.path.expanduser("~/Library/Application Support/InvoiceTimer")
    else:
        base = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
        base = os.path.join(base, "InvoiceTimer")
    return os.path.join(base, "config.json")


REGISTRY_PATH = os.path.abspath(os.environ.get("INVOICE_AUTOMATION_CONFIG", default_registry_path()))
RENDERER_PATH = os.path.join(BASE_DIR, "render_invoice.mjs")
TEMPLATE_PATH = os.path.join(BASE_DIR, "templates", "invoice.html")

MONTHS = {
    "January": 1, "February": 2, "March": 3, "April": 4,
    "May": 5, "June": 6, "July": 7, "August": 8,
    "September": 9, "October": 10, "November": 11, "December": 12,
}
TREATMENTS = {
    "intraState", "interState", "exportWithPayment",
    "exportWithoutPayment", "exempt",
}
REIMBURSEMENT_TREATMENTS = {"includedInTaxableValue", "excludedFromTaxableValue"}
MONEY = Decimal("0.01")


class ConfigError(ValueError):
    pass


def decimal_value(value, path):
    if isinstance(value, bool):
        raise ConfigError(f"{path} must be a number")
    try:
        result = Decimal(str(value))
    except Exception as exc:
        raise ConfigError(f"{path} must be a number") from exc
    if not result.is_finite():
        raise ConfigError(f"{path} must be finite")
    return result


def money(value):
    return decimal_value(value, "amount").quantize(MONEY, rounding=ROUND_HALF_UP)


def require(mapping, path, expected_type=None, allow_empty=False):
    current = mapping
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            raise ConfigError(f"Missing required config field: {path}")
        current = current[part]
    if expected_type is not None and not isinstance(current, expected_type):
        raise ConfigError(f"{path} must be {expected_type.__name__}")
    if not allow_empty and isinstance(current, str) and not current.strip():
        raise ConfigError(f"{path} must not be empty")
    return current


def parse_month(month_label):
    try:
        month_name, year_text = month_label.split()
        month_number = MONTHS[month_name]
        year_number = int(year_text)
    except (ValueError, KeyError) as exc:
        raise ConfigError(f"Invalid invoice month: {month_label!r}") from exc
    start = date(year_number, month_number, 1)
    next_month = date(year_number + (month_number == 12), month_number % 12 + 1, 1)
    return start, next_month - date.resolution, next_month


def active_config_path():
    with open(REGISTRY_PATH, encoding="utf-8") as stream:
        registry = json.load(stream)
    projects = require(registry, "projects", list)
    active = [project for project in projects if project.get("active")]
    if len(active) != 1:
        raise ConfigError("Exactly one project in config.json must have active=true")
    return require(active[0], "configPath", str)


def gst_applies(config, period_start):
    tax = config.get("taxProfile")
    if tax is None or tax.get("enabled") is False:
        return False
    if tax.get("enabled") is not True:
        raise ConfigError("taxProfile.enabled must be true or false")
    effective_text = require(tax, "effectiveFrom", str)
    try:
        effective_from = date.fromisoformat(effective_text)
    except ValueError as exc:
        raise ConfigError("taxProfile.effectiveFrom must use YYYY-MM-DD") from exc
    return period_start >= effective_from


def validate_party(config, key, gst_required):
    require(config, f"{key}.name", str)
    require(config, f"{key}.address", str)
    require(config, f"{key}.email", str, allow_empty=True)
    require(config, f"{key}.phone", str, allow_empty=True)
    if gst_required:
        gstin = require(config, f"{key}.gst.gstin", str).upper()
        state_code = require(config, f"{key}.gst.stateCode", str)
        require(config, f"{key}.gst.state", str)
        if len(gstin) != 15:
            raise ConfigError(f"{key}.gst.gstin must contain 15 characters")
        if len(state_code) != 2 or not state_code.isdigit():
            raise ConfigError(f"{key}.gst.stateCode must contain two digits")
        if gstin[:2] != state_code:
            raise ConfigError(f"{key}.gst.gstin prefix must match {key}.gst.stateCode")


def calculate_invoice(config, record, period_start):
    hours = decimal_value(require(record, "hours"), "invoice.hours")
    rate_usd = decimal_value(require(config, "rateUsd"), "rateUsd")
    exchange_rate = decimal_value(require(config, "exchRate"), "exchRate")
    if hours < 0 or rate_usd <= 0 or exchange_rate <= 0:
        raise ConfigError("hours cannot be negative and configured rates must be positive")

    service_amount = money(hours * rate_usd * exchange_rate)
    reimbursements = record.get("reimbursements", [])
    if not isinstance(reimbursements, list):
        raise ConfigError("invoice.reimbursements must be an array")

    tax_enabled = gst_applies(config, period_start)
    taxable_reimbursements = Decimal("0.00")
    excluded_reimbursements = Decimal("0.00")
    normalized_reimbursements = []
    reimbursement_settings = config.get("reimbursements", {})
    if not isinstance(reimbursement_settings, dict):
        raise ConfigError("reimbursements must be an object")
    reimbursement_treatment = reimbursement_settings.get("gstTreatment", "excludedFromTaxableValue")
    if reimbursement_treatment not in REIMBURSEMENT_TREATMENTS:
        raise ConfigError(
            "reimbursements.gstTreatment must be one of: "
            + ", ".join(sorted(REIMBURSEMENT_TREATMENTS))
        )
    for index, item in enumerate(reimbursements):
        if not isinstance(item, dict):
            raise ConfigError(f"invoice.reimbursements[{index}] must be an object")
        label = item.get("name", item.get("tool"))
        if not isinstance(label, str) or not label.strip():
            raise ConfigError(f"invoice.reimbursements[{index}].name must not be empty")
        amount = money(require(item, "amount"))
        if amount <= 0:
            raise ConfigError(f"invoice.reimbursements[{index}].amount must be greater than zero")
        if reimbursement_treatment == "includedInTaxableValue":
            taxable_reimbursements += amount
        else:
            excluded_reimbursements += amount
        normalized_reimbursements.append({"name": label.strip(), "amount": amount})

    taxable_value = money(service_amount + taxable_reimbursements)
    taxes = []
    tax_total = Decimal("0.00")
    tax = config.get("taxProfile", {})
    treatment = None
    if tax_enabled:
        validate_party(config, "from", True)
        validate_party(config, "client", True)
        sac_code = require(tax, "sacCode", str)
        require(tax, "sacDescription", str)
        if not sac_code.isdigit() or len(sac_code) not in (4, 6):
            raise ConfigError("taxProfile.sacCode must contain 4 or 6 digits")
        rate = decimal_value(require(tax, "ratePercent"), "taxProfile.ratePercent")
        if rate < 0 or rate > 100:
            raise ConfigError("taxProfile.ratePercent must be between 0 and 100")
        if require(tax, "amountsIncludeTax") is not False:
            raise ConfigError("Only taxProfile.amountsIncludeTax=false is currently supported")
        reverse_charge = require(tax, "reverseCharge")
        if not isinstance(reverse_charge, bool):
            raise ConfigError("taxProfile.reverseCharge must be true or false")
        treatment = require(tax, "defaultTreatment", str)
        if treatment not in TREATMENTS:
            raise ConfigError("Unsupported taxProfile.defaultTreatment: " + treatment)

        supplier_state = require(config, "from.gst.stateCode", str)
        client_state = require(config, "client.gst.stateCode", str)
        if treatment == "intraState" and supplier_state != client_state:
            raise ConfigError("intraState treatment requires matching supplier and client state codes")
        if treatment == "interState" and supplier_state == client_state:
            raise ConfigError("interState treatment requires different supplier and client state codes")

        if reverse_charge:
            taxes = []
        elif treatment == "intraState":
            half_rate = rate / Decimal("2")
            cgst = money(taxable_value * half_rate / Decimal("100"))
            sgst = money(taxable_value * half_rate / Decimal("100"))
            taxes = [("CGST", half_rate, cgst), ("SGST", half_rate, sgst)]
        elif treatment in {"interState", "exportWithPayment"}:
            igst = money(taxable_value * rate / Decimal("100"))
            taxes = [("IGST", rate, igst)]
        else:
            taxes = []
        tax_total = money(sum((item[2] for item in taxes), Decimal("0.00")))
    else:
        validate_party(config, "from", False)
        validate_party(config, "client", False)

    subtotal = money(service_amount + taxable_reimbursements + excluded_reimbursements)
    grand_total = money(taxable_value + tax_total + excluded_reimbursements)
    configured_amount = money(require(record, "amount"))
    if configured_amount != grand_total:
        raise ConfigError(
            f"invoice.amount is {configured_amount} but the deterministic total is {grand_total}"
        )
    return {
        "hours": hours, "rateInr": money(rate_usd * exchange_rate),
        "serviceAmount": service_amount, "reimbursements": normalized_reimbursements,
        "subtotal": subtotal, "taxableValue": taxable_value,
        "excludedReimbursements": money(excluded_reimbursements),
        "taxEnabled": tax_enabled, "treatment": treatment,
        "taxes": taxes, "taxTotal": tax_total, "grandTotal": grand_total,
    }


def indian_format(value):
    value = money(value)
    sign = "-" if value < 0 else ""
    whole, fraction = f"{abs(value):.2f}".split(".")
    if len(whole) > 3:
        tail, head = whole[-3:], whole[:-3]
        groups = []
        while head:
            groups.insert(0, head[-2:])
            head = head[:-2]
        whole = ",".join(groups + [tail])
    return f"{sign}{whole}.{fraction}"


def quantity_format(value):
    value = decimal_value(value, "quantity")
    if value == value.to_integral():
        return str(int(value))
    return format(value.normalize(), "f")


ONES = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
        "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen",
        "Seventeen", "Eighteen", "Nineteen"]
TENS = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]


def under_thousand(number):
    words = []
    if number >= 100:
        words.extend([ONES[number // 100], "Hundred"])
        number %= 100
    if number >= 20:
        words.append(TENS[number // 10])
        number %= 10
    if number:
        words.append(ONES[number])
    return " ".join(words)


def amount_in_words(value):
    value = money(value)
    rupees = int(value)
    paise = int((value - Decimal(rupees)) * 100)
    if rupees == 0:
        words = "Zero"
    else:
        parts = []
        for divisor, label in ((10_000_000, "Crore"), (100_000, "Lakh"), (1_000, "Thousand")):
            group, rupees = divmod(rupees, divisor)
            if group:
                parts.extend([under_thousand(group), label])
        if rupees:
            parts.append(under_thousand(rupees))
        words = " ".join(parts)
    suffix = f" and {under_thousand(paise)} Paise" if paise else ""
    return f"Indian Rupees {words}{suffix} Only"


def build_template_context(config, record, period_start, period_end, invoice_date, calc):
    bank = config.get("bank")
    if bank is not None:
        for field in ("name", "holder", "account", "ifsc"):
            require(bank, field, str)

    items = [{
        "description": "Development & Implementation",
        "detail": "Refer to attached timesheet for work log and hours",
        "sacCode": config["taxProfile"]["sacCode"] if calc["taxEnabled"] else None,
        "sacDescription": config["taxProfile"]["sacDescription"] if calc["taxEnabled"] else None,
        "quantity": quantity_format(calc["hours"]),
        "amount": indian_format(calc["serviceAmount"]),
    }]
    items.extend({
        "description": f'Reimbursement - {item["name"]}',
        "detail": "", "sacCode": None, "sacDescription": None,
        "quantity": "-", "amount": indian_format(item["amount"]),
    } for item in calc["reimbursements"])

    tax_rows = [{"name": name, "rate": quantity_format(rate), "amount": indian_format(amount)}
                for name, rate, amount in calc["taxes"]]
    return {
        "title": "INVOICE",
        "supplier": config["from"],
        "client": config["client"],
        "invoice": {
            "number": record["invoiceNo"],
            "date": invoice_date.strftime("%d %b %Y"),
            "period": f'{period_start.strftime("%d %b %Y")} - {period_end.strftime("%d %b %Y")}',
        },
        "items": items,
        "tax": {"enabled": calc["taxEnabled"], "rows": tax_rows},
        "totals": {
            "taxableValue": indian_format(calc["taxableValue"]),
            "grandTotal": indian_format(calc["grandTotal"]),
        },
        "rates": {"usd": quantity_format(config["rateUsd"]), "exchange": indian_format(config["exchRate"])},
        "bank": bank,
    }


def find_node():
    configured = os.environ.get("INVOICE_NODE")
    bundled = os.path.join(BASE_DIR, "runtime", "node")
    nvm_nodes = glob(os.path.expanduser("~/.nvm/versions/node/*/bin/node"))
    nvm_nodes.sort(
        key=lambda path: tuple(int(part) for part in path.split("/versions/node/v", 1)[1].split("/", 1)[0].split(".")),
        reverse=True,
    )
    candidates = [configured, bundled, *nvm_nodes, shutil.which("node")]
    for candidate in candidates:
        if candidate and os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            version = subprocess.run(
                [candidate, "--version"], check=False, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True
            ).stdout.strip().lstrip("v").split(".", 1)[0]
            if version.isdigit() and int(version) >= 20:
                return candidate
    raise ConfigError("Node.js 20 or newer was not found. Set INVOICE_NODE to a compatible executable.")


def render_invoice(context, output_path):
    if not os.path.isfile(TEMPLATE_PATH):
        raise ConfigError(f"Invoice template not found: {TEMPLATE_PATH}")
    if not os.path.isfile(RENDERER_PATH):
        raise ConfigError(f"Invoice renderer not found: {RENDERER_PATH}")
    with tempfile.TemporaryDirectory() as temp_dir:
        data_path = os.path.join(temp_dir, "invoice.json")
        with open(data_path, "w", encoding="utf-8") as stream:
            json.dump(context, stream, ensure_ascii=False)
        command = [find_node(), RENDERER_PATH, "--data", data_path, "--output", output_path]
        result = subprocess.run(command, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Invoice rendering failed: {result.stderr or result.stdout}")


def main():
    month_label = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else None
    if not month_label:
        raise SystemExit('Usage: python3 generate_invoice.py "August 2026"')
    config_path = active_config_path()
    with open(config_path, encoding="utf-8") as stream:
        config = json.load(stream)
    records = config.get("invoices", [])
    matches = [item for item in records if item.get("month") == month_label]
    if len(matches) != 1:
        raise ConfigError(f"Expected exactly one invoice record for {month_label}")
    record = matches[0]
    require(record, "invoiceNo", str)
    period_start, period_end, invoice_date = parse_month(month_label)
    calculation = calculate_invoice(config, record, period_start)

    output_dir = os.path.join(require(config, "outputDir", str), f"{record['invoiceNo']} {month_label}")
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, f"{record['invoiceNo']} Invoice - {month_label}.pdf")
    render_invoice(build_template_context(config, record, period_start, period_end, invoice_date, calculation), output_path)
    print(output_path)


if __name__ == "__main__":
    try:
        main()
    except (ConfigError, OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"Invoice generation failed: {exc}")
