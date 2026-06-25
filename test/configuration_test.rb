require "test_helper"

class PromptNavigatorConfigurationTest < ActiveSupport::TestCase
  setup do
    @original_platform_labels = PromptNavigator.config.platform_labels.dup
    @original_model_labels    = PromptNavigator.config.model_labels.dup
  end

  teardown do
    PromptNavigator.config.platform_labels = @original_platform_labels
    PromptNavigator.config.model_labels    = @original_model_labels
  end

  test "ships descriptive platform defaults" do
    assert_equal "GPT",    PromptNavigator.config.platform_labels["openai"]
    assert_equal "Claude", PromptNavigator.config.platform_labels["anthropic"]
    assert_equal "Gemini", PromptNavigator.config.platform_labels["google"]
    assert_equal "Ollama", PromptNavigator.config.platform_labels["ollama"]
  end

  test "model_labels starts empty" do
    assert_empty PromptNavigator.config.model_labels
  end

  test "label_for resolves per platform by default" do
    assert_equal "Claude", PromptNavigator.label_for(platform: "anthropic")
    assert_equal "GPT",    PromptNavigator.label_for(platform: "openai", model: "gpt-5")
  end

  test "label_for falls back to raw platform when unknown" do
    assert_equal "perplexity", PromptNavigator.label_for(platform: "perplexity")
  end

  test "label_for returns empty string when platform is nil/blank" do
    assert_equal "", PromptNavigator.label_for(platform: nil)
    assert_equal "", PromptNavigator.label_for(platform: "")
  end

  test "model_labels override platform_labels when matched" do
    PromptNavigator.configure do |c|
      c.model_labels["claude-opus-4-7"] = "Opus"
    end
    assert_equal "Opus",   PromptNavigator.label_for(platform: "anthropic", model: "claude-opus-4-7")
    assert_equal "Claude", PromptNavigator.label_for(platform: "anthropic", model: "claude-haiku-4-5")
  end

  test "host can override a platform label" do
    PromptNavigator.configure do |c|
      c.platform_labels["openai"] = "OAI"
    end
    assert_equal "OAI", PromptNavigator.label_for(platform: "openai")
  end

  test "configure block yields the same config object" do
    yielded = nil
    PromptNavigator.configure { |c| yielded = c }
    assert_same PromptNavigator.config, yielded
  end
end
