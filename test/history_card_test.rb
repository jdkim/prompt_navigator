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
end
