class HomeController < ApplicationController
  include ApplicationHelper

  DATA_PATH = Rails.root.join("data", "worldbank.json")

  def index
    session[:streak] ||= 0
    @global_high_score, @global_high_score_set_at = HighScore.best_in_past_week

    # Show "correct" result for 1.5s before next round (flash then redirect)
    if session[:correct_result].present?
      cr = session.delete(:correct_result)
      left_info = country_info(cr["left"])
      right_info = country_info(cr["right"])
      @show_correct_result = {
        left: cr["left"], right: cr["right"],
        left_name: left_info[:name], right_name: right_info[:name],
        left_flag_url: left_info[:flag_url], right_flag_url: right_info[:flag_url],
        left_value: cr["left_value"], right_value: cr["right_value"],
        winner: cr["winner"], indicator_label: indicator_label(cr["indicator"]),
        indicator_year: cr["indicator_year"]
      }
      @streak = session[:streak].to_i
      return
    end

    if session[:game_over]
      @game_over = true
      @result = session[:result] || {}
      @round = session[:result_round] # left/right/indicator for displaying the round we just lost
      data = load_data
      @indicator_year = data["indicatorYears"]&.[](@round["indicator"]) if @round.is_a?(Hash)
      @streak = session[:streak].to_i
      return
    end

    # Ensure we have a current round
    if session[:current_round].blank?
      data = load_data
      pair, indicator = build_round(data, session[:previous_winner])
      session[:current_round] = { "left" => pair[0], "right" => pair[1], "indicator" => indicator }
    end

    data = load_data
    round = session[:current_round]
    @round = {
      left: round["left"],
      right: round["right"],
      indicator: round["indicator"],
      indicator_label: indicator_label(round["indicator"]),
      indicator_year: data["indicatorYears"]&.[](round["indicator"])
    }
    @round[:left_name] = country_info(@round[:left])[:name]
    @round[:right_name] = country_info(@round[:right])[:name]
    @round[:left_flag_url] = country_info(@round[:left])[:flag_url]
    @round[:right_flag_url] = country_info(@round[:right])[:flag_url]
    @streak = session[:streak].to_i
  end

  def guess
    left = params[:left]
    right = params[:right]
    indicator = params[:indicator]
    guess_iso = params[:guess]

    data = load_data
    left_val = data["countries"][left]&.[](indicator)
    right_val = data["countries"][right]&.[](indicator)

    if left_val.nil? || right_val.nil?
      redirect_to root_path, alert: "Invalid round."
      return
    end

    if left_val == right_val
      correct = false
      winner = nil
    else
      winner = left_val > right_val ? left : right
      correct = (winner == guess_iso)
    end

    if correct
      session[:streak] = (session[:streak].to_i) + 1
      session[:previous_winner] = winner
      next_pair, next_indicator = build_round(data, session[:previous_winner])
      session[:current_round] = { "left" => next_pair[0], "right" => next_pair[1], "indicator" => next_indicator }
      session[:game_over] = false
      data = load_data
      session[:correct_result] = {
        "left" => left, "right" => right,
        "left_value" => left_val, "right_value" => right_val,
        "winner" => winner, "indicator" => indicator,
        "indicator_year" => data["indicatorYears"]&.[](indicator)
      }
      redirect_to root_path
    else
      streak = session[:streak].to_i
      HighScore.create!(streak: streak) if streak.positive?
      session[:game_over] = true
      session[:result] = {
        correct: false,
        winner: winner,
        left_value: left_val,
        right_value: right_val
      }
      session[:result_round] = { "left" => left, "right" => right, "indicator" => indicator }
      redirect_to root_path
    end
  end

  def restart
    session.delete(:game_over)
    session.delete(:result)
    session.delete(:result_round)
    session.delete(:previous_winner)
    session.delete(:current_round)
    session[:streak] = 0
    redirect_to root_path
  end

  private

  def load_data
    @cached_data ||= JSON.parse(File.read(DATA_PATH))
  end

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

      available = data["indicators"].select do |ind_key|
        val1 = data["countries"][left]&.[](ind_key)
        val2 = data["countries"][right]&.[](ind_key)
        val1.present? && val2.present?
      end

      if available.any?
        return [ [ left, right ], available.sample ]
      end
      break if attempts > 500
    end
    [ countries.sample(2), data["indicators"].first ]
  end
end
