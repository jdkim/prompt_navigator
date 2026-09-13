module PromptNavigator
  class PromptExecution < ApplicationRecord
    belongs_to :previous, class_name: "PromptNavigator::PromptExecution", optional: true

    # Reference edges this prompt carries. `supplements` are the executions
    # cited; `cited_by` is the reverse, needed so deleting a cited node can
    # clean up the edges pointing at it.
    has_many :supplement_links, -> { order(:position) },
             class_name: "PromptNavigator::Supplement",
             foreign_key: :prompt_execution_id,
             inverse_of: :prompt_execution,
             dependent: :delete_all
    has_many :supplements, through: :supplement_links, source: :supplement_execution
    has_many :citation_links,
             class_name: "PromptNavigator::Supplement",
             foreign_key: :supplement_execution_id,
             inverse_of: :supplement_execution,
             dependent: :delete_all

    before_create :set_execution_id

    # Builds a context array from the direct lineage for summarization.
    # Each entry contains { prompt:, response: } from ancestor PromptExecutions.
    # Optionally limit to the most recent N ancestors.
    def build_context(limit: nil)
      ancestors(limit: limit).map do
        { prompt: it.prompt, response: it.response }
      end
    end

    # Delete PromptExecutions safely — use this for a single row too, not only
    # for a set. `#delete` and `#delete_all` bypass callbacks, so `dependent:`
    # never fires and the supplement edges (a second self-referential FK into
    # this table) survive, making the delete fail with InvalidForeignKey.
    #
    # Bulk-delete a set of PromptExecutions, tolerating the self-referential
    # `previous_id` foreign key by first nulling intra-set links. Callers
    # (e.g. a host's Chat#destroy flow) pass the ids of orphaned executions
    # after their owning records (Messages) have been destroyed.
    #
    # Raises ActiveRecord::InvalidForeignKey if any PE in the set is still
    # referenced from outside the set (e.g. another chat's branch); callers
    # decide whether to rescue and leave the orphans in place.
    def self.delete_set!(ids)
      ids = Array(ids).compact
      return if ids.empty?

      # Supplement edges are a second self-referential FK into this table, in
      # both directions. `delete_all` bypasses callbacks, so `dependent:` never
      # fires here and the rows have to go first — otherwise deleting a chat
      # that used supplements raises InvalidForeignKey, which is exactly the
      # failure this method exists to prevent.
      #
      # Both directions go unconditionally, including citations made from
      # *outside* the set. That is deliberately unlike the `previous_id`
      # handling below, which only unlinks within the set and lets an outside
      # reference raise so the host can decide. The difference is that a
      # citation is a soft reference — losing it degrades one turn's context —
      # whereas a dangling previous_id would corrupt the lineage itself. It
      # also keeps a per-card delete of a cited leaf from failing with an
      # opaque FK error.
      Supplement.where(prompt_execution_id: ids).delete_all
      Supplement.where(supplement_execution_id: ids).delete_all

      where(id: ids).update_all(previous_id: nil)
      where(id: ids).delete_all
    end

    # Referenced material, grouped by identical prompt text.
    #
    # Supplements reach the model as *system context*, not as dialogue — that
    # is the whole meaning of the dotted arrow the history pane draws for them,
    # as against the solid arrow for the lineage that enters as conversation.
    # What the user wants done with the material (compare it, merge it, weigh
    # it) is said in the prompt itself and deliberately not modelled here:
    # intent is language, not schema.
    #
    # The common case is the same question put to several models — which the
    # Start node makes easy to produce — and repeating that question once per
    # model would both waste tokens and read as though the user had asked it
    # several times. Grouping collapses it to one question with N answers
    # labelled by model, which is also what lets a prompt refer to them in
    # words. A group of one renders as an ordinary question/answer pair, so
    # callers need no special case.
    #
    # Returns [{ prompt:, answers: [{ response:, model:, llm_platform: }, ...] }]
    # in selection order, the group taking the position of its first member.
    def supplement_groups
      self.class.group_supplements(supplements)
    end

    # The same grouping over an arbitrary list of executions, for callers that
    # do not have a saved prompt to read edges from — a composer previewing
    # what a *pending* selection would send, for instance. Sharing this with
    # the instance method above is the point: a preview that computed its own
    # grouping could drift from what actually gets sent.
    def self.group_supplements(nodes)
      Array(nodes).group_by { |pe| pe.prompt.to_s }.map do |prompt_text, group|
        {
          prompt: prompt_text,
          answers: group.map do |pe|
            { response: pe.response, model: pe.model, llm_platform: pe.llm_platform }
          end
        }
      end
    end

    private

    # Returns ancestor PromptExecutions in chronological order (oldest first),
    # excluding self. Optionally limit to the most recent N ancestors.
    def ancestors(limit: nil)
      chain = []
      pe = previous

      while pe
        chain.unshift(pe)
        pe = pe.previous
      end

      limit ? chain.last(limit) : chain
    end

    def set_execution_id
      self.execution_id ||= SecureRandom.uuid
    end
  end
end
