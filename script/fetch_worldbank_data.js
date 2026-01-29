import fs from "fs";

const BASE_URL = "https://api.worldbank.org/v2";
const YEAR = 2023;
const PER_PAGE = 300;

const indicators = {
  population: "SP.POP.TOTL",
  gdp_per_capita: "NY.GDP.PCAP.CD",
  life_expectancy: "SP.DYN.LE00.IN",
};

async function fetchJSON(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed: ${url}`);
  return res.json();
}

async function fetchCountries() {
  const url = `${BASE_URL}/country?format=json&per_page=${PER_PAGE}`;
  const data = await fetchJSON(url);
  return data[1].filter(c => c.region.value !== "Aggregates");
}

async function fetchIndicator(country, indicator) {
  const url = `${BASE_URL}/country/${country}/indicator/${indicator}?date=${YEAR}&format=json&per_page=1`;
  const data = await fetchJSON(url);
  return data?.[1]?.[0]?.value ?? null;
}

async function main() {
  const countries = await fetchCountries();
  const output = {};

  for (const country of countries) {
    const code = country.id;
    output[code] = {
      name: country.name,
      region: country.region.value,
      income_level: country.incomeLevel.value,
    };

    for (const [key, indicator] of Object.entries(indicators)) {
      output[code][key] = await fetchIndicator(code, indicator);
    }

    // be polite to the API
    await new Promise(r => setTimeout(r, 150));
  }

  fs.mkdirSync("data", { recursive: true });
  fs.writeFileSync(
    "data/countries_2023.json",
    JSON.stringify(output, null, 2)
  );

  console.log("✅ countries_2023.json generated");
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
