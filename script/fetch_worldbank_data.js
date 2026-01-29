import fs from "fs/promises";

const OUTPUT_FILE = "data/worldbank_2023.json";
const YEAR = 2023;
const PER_PAGE = 1000;

// Indicators to use in your game
const INDICATORS = {
  population: "SP.POP.TOTL",
  gdpPerCapita: "NY.GDP.PCAP.CD",
  lifeExpectancy: "SP.DYN.LE00.IN",
  medianAge: "SP.POP.MEDN"
};

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

async function safeFetchJSON(url) {
  try {
    console.log(`🌐 Fetching: ${url}`);
    const response = await fetch(url, {
      headers: {
        "User-Agent": "global-stats-game/1.0"
      }
    });

    const text = await response.text();

    try {
      return JSON.parse(text);
    } catch {
      console.warn("⚠️ Failed to parse JSON");
      return null;
    }
  } catch (err) {
    console.warn("⚠️ Network error:", err.message);
    return null;
  }
}

async function fetchAllCountries() {
  console.log("🌍 Fetching country list...");

  const url = `https://api.worldbank.org/v2/country?format=json&per_page=${PER_PAGE}`;
  const data = await safeFetchJSON(url);

  if (!Array.isArray(data) || !Array.isArray(data[1])) {
    throw new Error("Failed to fetch country list");
  }

  const countries = data[1]
    .filter(c => c.region?.id !== "NA") // exclude aggregates
    .map(c => c.id);

  console.log(`✅ Found ${countries.length} countries`);
  return countries;
}

async function fetchIndicator(country, indicator) {
  const url = `https://api.worldbank.org/v2/country/${country}/indicator/${indicator}?date=${YEAR}&format=json&per_page=1`;
  const data = await safeFetchJSON(url);

  if (!Array.isArray(data) || !Array.isArray(data[1])) {
    console.warn(`⚠️ ${country} ${indicator}: malformed response`);
    return null;
  }

  const value = data[1][0]?.value ?? null;

  if (value === null) {
    console.log(`➖ ${country} ${indicator}: no data`);
  } else {
    console.log(`✔️ ${country} ${indicator}: ${value}`);
  }

  return value;
}

async function main() {
  console.log("🚀 Starting World Bank data fetch");
  console.log(`📅 Target year: ${YEAR}`);

  const countries = await fetchAllCountries();
  const result = {};

  let countryCount = 0;

  for (const country of countries) {
    console.log(`\n🏳️ Processing ${country}`);
    result[country] = {};

    for (const [key, indicator] of Object.entries(INDICATORS)) {
      const value = await fetchIndicator(country, indicator);
      result[country][key] = value;

      // IMPORTANT: rate limit
      await sleep(150);
    }

    countryCount++;
    console.log(`✅ Finished ${country} (${countryCount}/${countries.length})`);
  }

  console.log("\n💾 Writing output file...");
  // ensure output directory exists
  await fs.mkdir("data", { recursive: true });

  await fs.writeFile(
    OUTPUT_FILE,
    JSON.stringify(
      {
        year: YEAR,
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
