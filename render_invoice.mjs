import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import nunjucks from "nunjucks";
import { chromium } from "playwright";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const value = (name) => {
  const index = args.indexOf(name);
  if (index < 0 || !args[index + 1]) throw new Error(`Missing ${name}`);
  return args[index + 1];
};

const dataPath = value("--data");
const outputPath = value("--output");
const data = JSON.parse(fs.readFileSync(dataPath, "utf8"));
const environment = nunjucks.configure(path.join(here, "templates"), {
  autoescape: true,
  noCache: true,
  throwOnUndefined: true,
});
const rendered = environment.render("invoice.html", data);
const bundledChromium = path.join(here, "runtime", "chromium", "chrome-headless-shell");
const chromiumExecutable = process.env.INVOICE_CHROMIUM
  || (fs.existsSync(bundledChromium) ? bundledChromium : chromium.executablePath());

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
const browser = await chromium.launch({
  headless: true,
  executablePath: chromiumExecutable,
});
try {
  const page = await browser.newPage();
  await page.setContent(rendered, { waitUntil: "load" });
  await page.emulateMedia({ media: "print" });
  await page.pdf({
    path: outputPath,
    format: "A4",
    printBackground: true,
    preferCSSPageSize: true,
  });
} finally {
  await browser.close();
}
process.stdout.write(`${outputPath}\n`);
