# frozen_string_literal: true

class CreateHighScores < ActiveRecord::Migration[7.2]
  def change
    create_table :high_scores do |t|
      t.integer :streak, null: false, default: 0

      t.timestamps
    end

    add_index :high_scores, :streak, order: { streak: :desc }
  end
end
