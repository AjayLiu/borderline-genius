require "net/http"

module ApplicationHelper
  # RestCountries doesn't include some territories; World Bank uses XKX for Kosovo
  FALLBACK_COUNTRIES = {
    "XKX" => { name: "Kosovo", flag_url: "https://flagcdn.com/xk.svg" }
  }.freeze

  def country_info(iso3)
    return { name: iso3, flag_url: "" } if iso3.blank?
    return FALLBACK_COUNTRIES[iso3.to_s.upcase].dup if FALLBACK_COUNTRIES.key?(iso3.to_s.upcase)

    cache_key = "country_info_#{iso3}"
    Rails.cache.fetch(cache_key, expires_in: 1.day) do
      uri = URI("https://restcountries.com/v3.1/alpha/#{iso3.downcase}")
      res = Net::HTTP.get_response(uri)
      unless res.is_a?(Net::HTTPSuccess)
        return FALLBACK_COUNTRIES[iso3.to_s.upcase].dup if FALLBACK_COUNTRIES.key?(iso3.to_s.upcase)
        return { name: iso3, flag_url: "" }
      end
      data = JSON.parse(res.body)
      c = data[0]
      info = { name: c["name"]["common"], flag_url: c.dig("flags", "svg").to_s }
      info[:flag_url] = FALLBACK_COUNTRIES[iso3.to_s.upcase][:flag_url] if info[:flag_url].blank? && FALLBACK_COUNTRIES.key?(iso3.to_s.upcase)
      info
    end
  end

  def format_stat_value(value)
    return "" if value.nil?
    return number_with_delimiter(value.to_i) if value.is_a?(Integer) || value == value.to_i
    format("%.2f", value)
  end

  def indicator_label(key)
    {
      "population" => "population",
      "gdpPerCapita" => "GDP per capita",
      "lifeExpectancy" => "life expectancy",
      "educationExpenditure" => "education expenditure (% of GDP)",
      "fertilityRate" => "fertility rate (births per woman)",
      "literacyRate" => "adult literacy rate (%)",
      "landArea" => "land area (sq km)",
      "renewableElectricity" => "renewable electricity (% of total)",
      "populationGrowth" => "population growth (annual %)",
      "unemploymentRate" => "unemployment rate (% of labor force)",
      "inflation" => "inflation, consumer prices (annual %)",
      "netMigration" => "net migration",
      "deathRate" => "death rate (per 1,000 people)",
      "diabetesPrevalence" => "diabetes prevalence (%)",
      "giniIndex" => "wealth inequality (Gini index)",
      "intentionalHomicides" => "intentional homicides (per 100,000 people)"
    }[key.to_s] || key.to_s
  end
end
