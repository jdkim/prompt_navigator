require "test_helper"

# Supplement edges let a prompt cite other executions whose content is
# injected as reference material for that one turn. The tree itself is
# untouched — `previous_id` stays exactly one parent — so what needs pinning
# here is the edge behaviour and, above all, that deletion still works: these
# edges are a *second* self-referential foreign key into the executions table,
# and `delete_set!` exists precisely to keep bulk deletion from tripping over
# such a key.
class PromptNavigator::SupplementTest < ActiveSupport::TestCase
  setup do
    PromptNavigator::Supplement.delete_all
    PromptNavigator::PromptExecution.delete_all
  end

  def pe(prompt:, response: "r", model: nil, platform: nil, previous: nil)
    PromptNavigator::PromptExecution.create!(
      prompt: prompt, response: response, model: model,
      llm_platform: platform, previous: previous
    )
  end

  def cite(execution, *supplements)
    supplements.each_with_index do |s, i|
      PromptNavigator::Supplement.create!(
        prompt_execution: execution, supplement_execution: s, position: i
      )
    end
    execution.reload
  end

  # ----- associations -----

  test "supplements come back in selection order, not insertion id order" do
    a = pe(prompt: "a")
    b = pe(prompt: "b")
    target = pe(prompt: "t")

    PromptNavigator::Supplement.create!(prompt_execution: target, supplement_execution: b, position: 0)
    PromptNavigator::Supplement.create!(prompt_execution: target, supplement_execution: a, position: 1)

    assert_equal [ b.id, a.id ], target.reload.supplements.map(&:id)
  end

  test "the same node cannot be cited twice by one prompt" do
    a = pe(prompt: "a")
    target = pe(prompt: "t")
    cite(target, a)

    assert_raises ActiveRecord::RecordNotUnique do
      PromptNavigator::Supplement.create!(prompt_execution: target, supplement_execution: a, position: 1)
    end
  end

  test "a prompt cannot cite itself" do
    a = pe(prompt: "a")
    edge = PromptNavigator::Supplement.new(prompt_execution: a, supplement_execution: a)

    assert_not edge.valid?
    assert_includes edge.errors[:supplement_execution], "cannot be the prompt itself"
  end

  # ----- deletion -----

  # The failure this guards against is concrete: without clearing the edges,
  # deleting a chat whose prompts used supplements raises InvalidForeignKey
  # and the whole destroy fails.
  test "delete_set! clears edges owned by the deleted prompts" do
    a = pe(prompt: "a")
    target = pe(prompt: "t")
    cite(target, a)

    PromptNavigator::PromptExecution.delete_set!([ target.id, a.id ])

    assert_equal 0, PromptNavigator::Supplement.count
    assert_equal 0, PromptNavigator::PromptExecution.count
  end

  # The reverse direction matters just as much: the cited node is referenced
  # by an edge it does not own.
  test "delete_set! clears edges pointing AT the deleted prompts" do
    cited = pe(prompt: "cited")
    citer = pe(prompt: "citer")
    cite(citer, cited)

    PromptNavigator::PromptExecution.delete_set!([ cited.id, citer.id ])

    assert_equal 0, PromptNavigator::Supplement.count
  end

  # The two cleanup directions are only distinguishable when a single endpoint
  # is in the deleted set. With both endpoints inside, either query alone
  # removes the row, so a test like the two above cannot tell them apart.
  test "delete_set! drops a deleted prompt's own citations, cited node surviving" do
    cited = pe(prompt: "cited")
    citer = pe(prompt: "citer")
    cite(citer, cited)

    PromptNavigator::PromptExecution.delete_set!([ citer.id ])

    assert_equal 0, PromptNavigator::Supplement.count
    assert PromptNavigator::PromptExecution.exists?(cited.id), "the cited node was not being deleted"
  end

  # Deleting a node someone else cites drops the citation rather than raising.
  # That is deliberately unlike `previous_id`, where an outside reference is
  # left to blow up so the host can decide: a citation is a soft reference, so
  # losing it degrades one turn's context, whereas a dangling previous_id would
  # corrupt the lineage itself. It also keeps the pane's per-card delete from
  # failing with an opaque FK error on a leaf that happens to be cited.
  test "delete_set! drops citations pointing at a deleted node, citer surviving" do
    cited = pe(prompt: "cited")
    citer = pe(prompt: "citer")
    cite(citer, cited)

    PromptNavigator::PromptExecution.delete_set!([ cited.id ])

    assert_equal 0, PromptNavigator::Supplement.count
    assert PromptNavigator::PromptExecution.exists?(citer.id), "the citing node was not being deleted"
    assert_empty citer.reload.supplements
  end

  test "delete_set! still deletes a plain chain that has no edges at all" do
    root = pe(prompt: "p1")
    leaf = pe(prompt: "p2", previous: root)

    PromptNavigator::PromptExecution.delete_set!([ root.id, leaf.id ])

    assert_equal 0, PromptNavigator::PromptExecution.count
  end

  # ----- grouping -----

  # The headline case: one question put to several models. Repeating the
  # question once per model would waste tokens and read as though the user had
  # asked it several times.
  test "identical prompts collapse into one group with one answer per model" do
    q = "Which treatment?"
    claude = pe(prompt: q, response: "answer A", model: "claude-fable-5-1", platform: "anthropic")
    gpt    = pe(prompt: q, response: "answer B", model: "gpt-5.6-terra", platform: "openai")
    target = pe(prompt: "compare them")
    cite(target, claude, gpt)

    groups = target.supplement_groups

    assert_equal 1, groups.length
    assert_equal q, groups[0][:prompt]
    assert_equal [ "answer A", "answer B" ], groups[0][:answers].map { |a| a[:response] }
    assert_equal [ "claude-fable-5-1", "gpt-5.6-terra" ], groups[0][:answers].map { |a| a[:model] }
  end

  test "distinct prompts stay in separate single-answer groups" do
    a = pe(prompt: "question one", response: "r1")
    b = pe(prompt: "question two", response: "r2")
    target = pe(prompt: "t")
    cite(target, a, b)

    groups = target.supplement_groups

    assert_equal [ "question one", "question two" ], groups.map { |g| g[:prompt] }
    assert_equal [ 1, 1 ], groups.map { |g| g[:answers].length }
  end

  test "a mixed selection groups only the matching prompts" do
    q = "shared"
    s1 = pe(prompt: q, response: "r1")
    s2 = pe(prompt: q, response: "r2")
    other = pe(prompt: "different", response: "r3")
    target = pe(prompt: "t")
    cite(target, s1, s2, other)

    groups = target.supplement_groups

    assert_equal 2, groups.length
    assert_equal [ 2, 1 ], groups.map { |g| g[:answers].length }
  end

  # The lineage parent is NOT reference material — it reaches the model as
  # dialogue. Only cited nodes appear here, even when the parent is one of
  # them by coincidence of being cited explicitly.
  test "the lineage parent is absent unless it was explicitly cited" do
    primary = pe(prompt: "q", response: "primary answer")
    target  = pe(prompt: "t", previous: primary)

    assert_empty target.supplement_groups
  end

  test "a cited parent does appear, because citing is what puts it there" do
    primary = pe(prompt: "q", response: "primary answer")
    target  = pe(prompt: "t", previous: primary)
    cite(target, primary)

    assert_equal [ "primary answer" ], target.supplement_groups.flat_map { |g| g[:answers].map { |a| a[:response] } }
  end

  test "supplement_groups is empty when nothing was cited" do
    assert_empty pe(prompt: "t").supplement_groups
  end
end
