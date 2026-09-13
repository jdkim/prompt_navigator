require "test_helper"

# Render-level tests for the _history_card partial's straight-arrow logic.
# Covers both ordering directions (newest-first → "↑", oldest-first → "↓")
# and the no-arrow case when the next card isn't directly related.
class HistoryCardArrowTest < ActionView::TestCase
  include PromptNavigator::Engine.routes.url_helpers

  setup do
    @parent = PromptNavigator::PromptExecution.create!(prompt: "p", response: "r")
    @child  = PromptNavigator::PromptExecution.create!(prompt: "c", response: "r", previous: @parent)
    @unrelated = PromptNavigator::PromptExecution.create!(prompt: "u", response: "r")
    @card_path   = ->(_uuid) { "#" }
    @delete_path = ->(_uuid) { "#" }
  end

  def render_card(ann:, next_ann:)
    # Match the production call form in _history.html.erb: string-first render,
    # where the whole options hash becomes the partial's locals — so `locals:`
    # arrives as a local variable named `locals` holding the inner hash.
    render "prompt_navigator/history_card", locals: {
      ann: ann, next_ann: next_ann, is_active: false,
      card_path: @card_path, delete_path: @delete_path, is_leaf: true
    }
  end

  test "renders ↑ when next card is the parent (newest-first ordering)" do
    out = render_card(ann: @child, next_ann: @parent)
    assert_includes out, "↑"
    assert_not_includes out, "↓"
  end

  test "renders ↓ when next card is the child (oldest-first ordering)" do
    out = render_card(ann: @parent, next_ann: @child)
    assert_includes out, "↓"
    assert_not_includes out, "↑"
  end

  test "renders no arrow when next card is unrelated" do
    out = render_card(ann: @child, next_ann: @unrelated)
    assert_not_includes out, "↑"
    assert_not_includes out, "↓"
  end

  test "renders no arrow when there is no next card" do
    out = render_card(ann: @child, next_ann: nil)
    assert_not_includes out, "↑"
    assert_not_includes out, "↓"
  end

  # ----- preview-stripping of attached-file data URIs -----

  test "strips leading image data URI in the preview and replaces with [image]" do
    pe = PromptNavigator::PromptExecution.create!(
      prompt: "![](data:image/png;base64,AAAAAAAAAAAA)describe this",
      response: "r"
    )
    out = render_card(ann: pe, next_ann: nil)
    assert_includes out, "[image]describe this"
    assert_not_includes out, "AAAAAAAAAAAA"
  end

  test "strips leading document data URI and shows the filename in brackets" do
    pe = PromptNavigator::PromptExecution.create!(
      prompt: "[report.pdf](data:application/pdf;base64,JVBERi0xLjQ)summarize this",
      response: "r"
    )
    out = render_card(ann: pe, next_ann: nil)
    assert_includes out, "[report.pdf]summarize this"
    assert_not_includes out, "JVBERi0xLjQ"
  end

  test "falls back to [document] when the doc data URI has an empty filename" do
    pe = PromptNavigator::PromptExecution.create!(
      prompt: "[](data:text/plain;base64,QQ==)what is it",
      response: "r"
    )
    out = render_card(ann: pe, next_ann: nil)
    assert_includes out, "[document]what is it"
  end

  test "does NOT strip a regular markdown link (non-data URI) in the preview" do
    pe = PromptNavigator::PromptExecution.create!(
      prompt: "see [my-docs](https://example.org/foo)",
      response: "r"
    )
    out = render_card(ann: pe, next_ann: nil)
    # The 30-char preview cap will truncate the URL — the key point is that
    # the link syntax is NOT rewritten (which the data-URI strip would do).
    assert_includes out, "see [my-docs]("
    assert_not_includes out, "[document]"
  end

  # Supplement edges reach the arrow renderer through this attribute. The
  # renderer reads `data-supplement-uuids` off each card and draws one dotted
  # arrow per entry, so an omission here silently loses every reference arrow
  # with no error anywhere.
  test "emits the cited nodes as data-supplement-uuids, in selection order" do
    a = PromptNavigator::PromptExecution.create!(prompt: "a", response: "r")
    b = PromptNavigator::PromptExecution.create!(prompt: "b", response: "r")
    PromptNavigator::Supplement.create!(prompt_execution: @child, supplement_execution: b, position: 0)
    PromptNavigator::Supplement.create!(prompt_execution: @child, supplement_execution: a, position: 1)

    out = render_card(ann: @child.reload, next_ann: nil)

    assert_includes out, %(data-supplement-uuids="#{b.execution_id},#{a.execution_id}")
  end

  test "emits an empty data-supplement-uuids when nothing was cited" do
    out = render_card(ann: @child, next_ann: nil)

    assert_includes out, %(data-supplement-uuids="")
  end

  # The lineage arrow and the supplement arrows are separate channels; citing
  # a node must not disturb the parent attribute the solid arrow depends on.
  test "citing a node leaves the lineage parent attribute untouched" do
    other = PromptNavigator::PromptExecution.create!(prompt: "o", response: "r")
    PromptNavigator::Supplement.create!(prompt_execution: @child, supplement_execution: other, position: 0)

    out = render_card(ann: @child.reload, next_ann: nil)

    assert_includes out, %(data-parent-uuid="#{@parent.execution_id}")
  end
end
