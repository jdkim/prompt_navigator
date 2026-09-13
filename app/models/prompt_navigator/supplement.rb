module PromptNavigator
  # A reference edge: `prompt_execution` cites `supplement_execution`, whose
  # content is injected as reference material for that one turn.
  #
  # Kept as a join model rather than a column on PromptExecution because a
  # prompt may cite several nodes, and because the edge carries its own
  # ordering.
  class Supplement < ApplicationRecord
    belongs_to :prompt_execution,
               class_name: "PromptNavigator::PromptExecution"
    belongs_to :supplement_execution,
               class_name: "PromptNavigator::PromptExecution"

    validate :cannot_reference_itself

    private

    # A prompt citing itself would duplicate its own text into its own
    # reference block. Nothing in the UI offers it, but the edge is cheap to
    # forbid and expensive to debug.
    def cannot_reference_itself
      return if prompt_execution_id.nil?
      return unless prompt_execution_id == supplement_execution_id

      errors.add(:supplement_execution, "cannot be the prompt itself")
    end
  end
end
