require "test_helper"

# What the history sidebar shows for a turn.
#
# The label used to be resolved entirely from the host's LIVE catalog, so it
# described what is offered TODAY rather than what actually answered. Retiring a
# model silently rewrote history: on one production database 350 of 520 turns had
# already decayed to the bare platform name, Ollama-hosted ones included — which
# is the very case the per-model label was added for. A turn now captures its
# label when it is written.
class PromptNavigator::DisplayLabelTest < ActiveSupport::TestCase
  setup do
    @original = PromptNavigator.config.model_labels.dup
    PromptNavigator.config.model_labels.replace({})
  end

  teardown { PromptNavigator.config.model_labels.replace(@original) }

  def execution(**attrs)
    PromptNavigator::PromptExecution.new(prompt: "p", **attrs)
  end

  test "a stored label survives the model leaving the catalog" do
    pe = execution(llm_platform: "google", model: "gemini-2-5-flash-image",
                   model_label: "Gemini 2.5 Flash Image (Nano Banana)")
    # Nothing registered — exactly the state after the model is retired.
    assert_equal "Gemini 2.5 Flash Image (Nano Banana)", pe.display_label
  end

  test "a stored label wins over a differently-registered one" do
    PromptNavigator.configure { |c| c.model_labels["m"] = "Renamed Since" }
    pe = execution(llm_platform: "google", model: "m", model_label: "As It Was")
    assert_equal "As It Was", pe.display_label
  end

  test "without a stored label it resolves live, as before" do
    PromptNavigator.configure { |c| c.model_labels["m"] = "Live Label" }
    assert_equal "Live Label", execution(llm_platform: "google", model: "m").display_label
  end

  test "an unregistered model with no stored label still falls back to the platform" do
    assert_equal "Gemini", execution(llm_platform: "google", model: "gone").display_label
  end

  test "a blank stored label is ignored rather than rendering empty" do
    pe = execution(llm_platform: "google", model: "gone", model_label: "")
    assert_equal "Gemini", pe.display_label
  end
end
