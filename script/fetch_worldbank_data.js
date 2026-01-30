import fs from "fs/promises";

const OUTPUT_FILE = "data/worldbank.json";
// Use a year range and keep the most recent non-null value per country/indicator (best coverage)
const DATE_RANGE = "2015:2025";
const PER_PAGE = 1000;

// Indicators to use in your game (World Bank codes)
const INDICATORS = {
  population: "SP.POP.TOTL",
  gdpPerCapita: "NY.GDP.PCAP.CD",
  lifeExpectancy: "SP.DYN.LE00.IN",
  educationExpenditure: "SE.XPD.TOTL.GD.ZS",
  fertilityRate: "SP.DYN.TFRT.IN",
  literacyRate: "SE.ADT.LITR.ZS",
  landArea: "AG.LND.TOTL.K2",
  renewableElectricity: "EG.FEC.RNEW.ZS",
  populationGrowth: "SP.POP.GROW",
  unemploymentRate: "SL.UEM.TOTL.ZS",
  inflation: "FP.CPI.TOTL.ZG",
  netMigration: "SM.POP.NETM",
  deathRate: "SP.DYN.CDRT.IN",
  diabetesPrevalence: "SH.STA.DIAB.ZS",
  giniIndex: "SI.POV.GINI",
  intentionalHomicides: "VC.IHR.PSRC.P5"
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function safeFetchJSON(url, attempts = 3) {
  for (let i = 0; i < attempts; i++) {
    try {
      console.log(`🌐 Fetching: ${url}`);
      const response = await fetch(url, {
        headers: {
          "User-Agent": "global-stats-game/1.0",
        },
      });

      const text = await response.text();
      try {
        return JSON.parse(text);
      } catch {
        console.warn("⚠️ Failed to parse JSON");
        return null;
      }
    } catch (err) {
      console.warn(`⚠️ Network error (attempt ${i + 1}):`, err.message);
      if (i < attempts - 1) {
        await sleep(500 * (i + 1));
        continue;
      }
      return null;
    }
  }
}

async function fetchAllCountries() {
  console.log("🌍 Fetching country list...");
  const url = `https://api.worldbank.org/v2/country?format=json&per_page=${PER_PAGE}`;
  const data = await safeFetchJSON(url);

  if (!Array.isArray(data) || !Array.isArray(data[1])) {
    throw new Error("Failed to fetch country list");
  }

  const countries = data[1].filter((c) => c.region?.id !== "NA").map((c) => c.id);
  console.log(`✅ Found ${countries.length} countries`);
  return countries;
}

// Fetch values for a single indicator across all countries in one request (much faster).
async function fetchIndicatorBulk(indicator) {
  const urlBase = `https://api.worldbank.org/v2/country/all/indicator`;
  const codes = [indicator];
  return await fetchIndicatorsBulk(codes);
}

async function main() {
  console.log("🚀 Starting World Bank data fetch");
  console.log(`📅 Date range: ${DATE_RANGE} (one year per indicator = fair comparison)`);

  const countries = await fetchAllCountries();
  const result = {};
  for (const c of countries) result[c] = {};

  // Build inverse map: indicator code -> our key name (e.g., "SP.POP.TOTL" -> "population")
  const codeToKey = Object.fromEntries(
    Object.entries(INDICATORS).map(([k, v]) => [v, k])
  );

  const indicatorYears = {}; // which year we used per indicator (for metadata)

  // Fetch each indicator across all countries (one indicator per request)
  const codes = Object.values(INDICATORS);
  for (const indicatorCode of codes) {
    console.log(`🚄 Fetching indicator ${indicatorCode} across all countries...`);
    const entries = await fetchIndicatorsBulk([indicatorCode]);
    if (!Array.isArray(entries)) continue;

    // 1) Pick ONE year per indicator: the year with the most countries that have non-null data (fair comparison)
    const countByYear = {};
    for (const e of entries) {
      if (e.value == null || !e.date) continue;
      if (!(e.countryId in result)) continue; // only our country list
      countByYear[e.date] = (countByYear[e.date] || 0) + 1;
    }
    let bestYear = null;
    let maxCount = 0;
    for (const [y, count] of Object.entries(countByYear)) {
      const yr = Number(y);
      if (isNaN(yr)) continue;
      if (count > maxCount || (count === maxCount && yr > Number(bestYear))) {
        maxCount = count;
        bestYear = y;
      }
    }
    const key = codeToKey[indicatorCode];
    if (key) indicatorYears[key] = bestYear ? Number(bestYear) : null;

    // 2) Use only values from that year for this indicator (same year for every country)
    for (const e of entries) {
      if (e.countryId in result && e.indicatorCode === indicatorCode && e.date === bestYear && e.value != null) {
        result[e.countryId][key] = e.value;
      }
    }
  }

  // helper: fetch multiple indicators in bulk (handles pagination and chunking)
  async function fetchIndicatorsBulk(codes) {
    // API limits: recommend chunking if many indicators; keep safe upper bound
    const MAX_PER_REQUEST = 50;
    const chunks = [];
    for (let i = 0; i < codes.length; i += MAX_PER_REQUEST) {
      chunks.push(codes.slice(i, i + MAX_PER_REQUEST));
    }

    const allEntries = [];
    for (const chunk of chunks) {
      const indicatorPath = chunk.join(";");
      let page = 1;
      let pages = 1;
      do {
        const url = `https://api.worldbank.org/v2/country/all/indicator/${indicatorPath}?date=${DATE_RANGE}&format=json&per_page=${PER_PAGE}&page=${page}`;
        const data = await safeFetchJSON(url);
        if (!Array.isArray(data) || !Array.isArray(data[1])) {
          console.warn(`⚠️ Indicators ${indicatorPath} page ${page}: malformed response`);
          break;
        }
        // metadata in data[0]
        if (data[0] && data[0].pages) pages = Number(data[0].pages) || 1;

        for (const entry of data[1]) {
          const countryId = entry.countryiso3code || entry.country?.id;
          const indicatorCode = entry.indicator?.id;
          const value = entry.value ?? null;
          const date = entry.date || "";
          if (!countryId || !indicatorCode) continue;
          allEntries.push({ countryId, indicatorCode, value, date });
        }

        page++;
        // be kind to API
        await sleep(100);
      } while (page <= pages);
    }
    return allEntries;
  }

  console.log("\n💾 Writing output file...");
  // ensure output directory exists
  await fs.mkdir("data", { recursive: true });

  await fs.writeFile(
    OUTPUT_FILE,
    JSON.stringify(
      {
        dateRange: DATE_RANGE,
        indicatorYears,
        generatedAt: new Date().toISOString(),
        indicators: Object.keys(INDICATORS),
        countries: result
      },
      null,
      2
    )
  );

  console.log(`🎉 Done! Saved to ${OUTPUT_FILE}`);
}

main().catch(err => {
  console.error("🔥 Fatal error:", err);
  process.exit(1);
});
