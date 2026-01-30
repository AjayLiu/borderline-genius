# frozen_string_literal: true

class HighScore < ApplicationRecord
  validates :streak, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  scope :past_week, -> { where("created_at >= ?", 1.week.ago) }

  # Returns [streak, set_at]; streak defaults to 0, set_at nil when no record in past week.
  def self.best_in_past_week
    record = past_week.order(streak: :desc).first
    record ? [record.streak, record.created_at] : [0, nil]
  end
end
