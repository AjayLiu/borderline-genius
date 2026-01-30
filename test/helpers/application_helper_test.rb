# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActiveSupport::TestCase
  include ApplicationHelper

  DATA_PATH = Rails.root.join("data", "worldbank.json")

  test "indicator_label returns a string for known keys" do
    assert_equal "population", indicator_label("population")
    assert_equal "GDP per capita", indicator_label("gdpPerCapita")
    assert indicator_label("unknown_key").is_a?(String)
  end

  test "all worldbank countries have valid name and flag" do
    skip "data/worldbank.json not present (run fetch script)" unless DATA_PATH.exist?
    skip "skipped in CI (hits RestCountries API)" if ENV["CI"]

    data = JSON.parse(File.read(DATA_PATH))
    country_codes = data["countries"].keys

    missing_name = []
    missing_flag = []

    country_codes.each do |iso3|
      info = country_info(iso3)
      missing_name << iso3 if info[:name].blank?
      missing_flag << iso3 if info[:flag_url].blank?
    end

    assert missing_name.empty?,
           "Countries missing name (#{missing_name.size}): #{missing_name.join(', ')}"
    assert missing_flag.empty?,
           "Countries missing flag_url (#{missing_flag.size}): #{missing_flag.join(', ')}"
  end
end
