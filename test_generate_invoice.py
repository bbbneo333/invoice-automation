import unittest
from datetime import date
from decimal import Decimal

from generate_invoice import ConfigError, build_template_context, calculate_invoice, quantity_format


def base_config():
    return {
        "rateUsd": 25,
        "exchRate": 91,
        "reimbursements": {"gstTreatment": "excludedFromTaxableValue"},
        "from": {
            "name": "Supplier", "address": "Jaipur", "email": "", "phone": "",
            "gst": {"gstin": "08AAAAA0000A1Z5", "state": "Rajasthan", "stateCode": "08"},
        },
        "client": {
            "name": "Customer", "address": "Jaipur", "email": "", "phone": "",
            "gst": {"gstin": "08BBBBB0000B1Z4", "state": "Rajasthan", "stateCode": "08"},
        },
        "taxProfile": {
            "enabled": True, "effectiveFrom": "2026-08-01", "sacCode": "998314",
            "sacDescription": "Information technology design and development services",
            "ratePercent": 18, "amountsIncludeTax": False, "reverseCharge": False,
            "defaultTreatment": "intraState",
        },
    }


class InvoiceCalculationTests(unittest.TestCase):
    def test_quantity_format_preserves_integer_zeroes(self):
        self.assertEqual(quantity_format(160), "160")
        self.assertEqual(quantity_format(158.5), "158.5")

    def test_intra_state_gst(self):
        result = calculate_invoice(
            base_config(), {"hours": 160, "amount": 429520, "reimbursements": []}, date(2026, 8, 1)
        )
        self.assertEqual(result["serviceAmount"], Decimal("364000.00"))
        self.assertEqual(result["taxes"][0][2], Decimal("32760.00"))
        self.assertEqual(result["taxes"][1][2], Decimal("32760.00"))
        self.assertEqual(result["grandTotal"], Decimal("429520.00"))

    def test_before_gst_effective_date_has_no_tax(self):
        result = calculate_invoice(
            base_config(), {"hours": 160, "amount": 364000, "reimbursements": []}, date(2026, 7, 1)
        )
        self.assertFalse(result["taxEnabled"])
        self.assertEqual(result["grandTotal"], Decimal("364000.00"))

    def test_taxable_reimbursement(self):
        config = base_config()
        config["reimbursements"]["gstTreatment"] = "includedInTaxableValue"
        result = calculate_invoice(config, {
            "hours": 1, "amount": 3862.14,
            "reimbursements": [{"name": "Tool", "amount": 998}],
        }, date(2026, 8, 1))
        self.assertEqual(result["taxableValue"], Decimal("3273.00"))
        self.assertEqual(result["grandTotal"], Decimal("3862.14"))

    def test_reimbursement_uses_project_level_excluded_treatment(self):
        result = calculate_invoice(base_config(), {
            "hours": 1, "amount": 3189.50,
            "reimbursements": [{"name": "Tool", "amount": 505}],
        }, date(2026, 8, 1))
        self.assertEqual(result["taxableValue"], Decimal("2275.00"))
        self.assertEqual(result["grandTotal"], Decimal("3189.50"))

    def test_intra_state_mismatch_fails(self):
        config = base_config()
        config["client"]["gst"] = {
            "gstin": "29BBBBB0000B1Z4", "state": "Karnataka", "stateCode": "29"
        }
        with self.assertRaisesRegex(ConfigError, "matching"):
            calculate_invoice(config, {"hours": 1, "amount": 0, "reimbursements": []}, date(2026, 8, 1))

    def test_reverse_charge_does_not_charge_tax(self):
        config = base_config()
        config["taxProfile"]["reverseCharge"] = True
        result = calculate_invoice(
            config, {"hours": 1, "amount": 2275, "reimbursements": []}, date(2026, 8, 1)
        )
        self.assertEqual(result["taxes"], [])
        self.assertEqual(result["grandTotal"], Decimal("2275.00"))

    def test_template_context_contains_display_ready_tax_rows(self):
        config = base_config()
        record = {"invoiceNo": "007", "hours": 160, "amount": 429520, "reimbursements": []}
        result = calculate_invoice(config, record, date(2026, 8, 1))
        context = build_template_context(
            config, record, date(2026, 8, 1), date(2026, 8, 31), date(2026, 9, 1), result
        )
        self.assertEqual(context["items"][0]["sacCode"], "998314")
        self.assertEqual(context["tax"]["rows"][0], {"name": "CGST", "rate": "9", "amount": "32,760.00"})
        self.assertEqual(context["totals"]["grandTotal"], "4,29,520.00")


if __name__ == "__main__":
    unittest.main()
