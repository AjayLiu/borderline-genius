class GameController < ApplicationController
  protect_from_forgery with: :null_session, only: [ :guess ]

  DATA_PATH = Rails.root.join("data", "worldbank.json")

  def round
    data = load_data
    pair, indicator = build_round(data, session[:previous_winner])
    session[:current_round] = { left: pair[0], right: pair[1], indicator: indicator }

    render json: {
      left: pair[0],
      right: pair[1],
      indicator: indicator,
      indicator_label: indicator_label(indicator)
    }
  end

  def guess
    payload = params.permit(:left, :right, :indicator, :guess)
    data = load_data

    left = payload[:left]
    right = payload[:right]
    indicator = payload[:indicator]
    guess = payload[:guess]

    left_val = data["countries"][left]&.[](indicator)
    right_val = data["countries"][right]&.[](indicator)

    # If any value missing, reject
    if left_val.nil? || right_val.nil?
      render json: { error: "Indicator value missing for one of the countries" }, status: :unprocessable_entity
      return
    end

    if left_val == right_val
      correct = false
      winner = nil
    else
      winner_iso = left_val > right_val ? left : right
      correct = (winner_iso == guess)
      winner = winner_iso
    end

    # set previous_winner only if guess was correct
    if correct
      session[:previous_winner] = winner
    else
      session[:previous_winner] = nil
    end

    # always prepare a next round (uses previous_winner which may be nil)
    next_pair, next_indicator = build_round(data, session[:previous_winner])
    session[:current_round] = { left: next_pair[0], right: next_pair[1], indicator: next_indicator }
    next_round = {
      left: next_pair[0],
      right: next_pair[1],
      indicator: next_indicator,
      indicator_label: indicator_label(next_indicator)
    }

    render json: {
      correct: correct,
      winner: winner,
      left_value: left_val,
      right_value: right_val,
      next_round: next_round
    }
  end

  private

  def load_data
    @cached_data ||= JSON.parse(File.read(DATA_PATH))
  end

  # Return [ [left_iso3, right_iso3], indicator_key ]
  def build_round(data, previous_winner = nil)
    countries = data["countries"].keys
    attempts = 0
    loop do
      attempts += 1
      if previous_winner.present? && data["countries"].key?(previous_winner)
        left = previous_winner
        right = (countries - [ left ]).sample
      else
        pair = countries.sample(2)
        left, right = pair[0], pair[1]
      end

      # find indicators where both values are present
      available = data["indicators"].select do |ind_key|
        val1 = data["countries"][left]&.[](ind_key)
        val2 = data["countries"][right]&.[](ind_key)
        !val1.nil? && !val2.nil?
      end

      if available.any?
        indicator = available.sample
        return [ [ left, right ], indicator ]
      end

      # safety break
      break if attempts > 500
      # otherwise try another pair
    end

    # fallback: return any two countries with at least one non-nil across them
    [ [ countries[0], countries[1] ], data["indicators"].first ]
  end

  def indicator_label(key)
    {
      "population" => "population",
      "gdpPerCapita" => "GDP per capita",
      "lifeExpectancy" => "life expectancy",
      "educationExpenditure" => "education expenditure (% of GDP)",
      "fertilityRate" => "fertility rate (births per woman)",
      "literacyRate" => "adult literacy rate (%)"
    }[key] || key
  end
end
