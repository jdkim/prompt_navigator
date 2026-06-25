# frozen_string_literal: true

module PromptNavigator
  # Host-overridable display config for the history sidebar.
  #
  # Usage from a host app initializer:
  #
  #   PromptNavigator.configure do |c|
  #     c.platform_labels["openai"] = "OAI"           # override platform default
  #     c.model_labels["claude-opus-4-7"] = "Opus"    # per-model override
  #   end
  class Configuration
    DEFAULT_PLATFORM_LABELS = {
      "openai"    => "GPT",
      "anthropic" => "Claude",
      "google"    => "Gemini",
      "ollama"    => "Ollama"
    }.freeze

    attr_accessor :platform_labels, :model_labels

    def initialize
      @platform_labels = DEFAULT_PLATFORM_LABELS.dup
      @model_labels    = {}
    end
  end

  def self.config
    @config ||= Configuration.new
  end

  def self.configure
    yield config
  end

  # Resolution order: per-model override → per-platform → raw platform string.
  # Returns "" only when both inputs are blank.
  def self.label_for(platform:, model: nil)
    model_key = model.to_s
    return config.model_labels[model_key] if model_key != "" && config.model_labels.key?(model_key)
    platform_key = platform.to_s
    config.platform_labels[platform_key] || platform_key
  end
end
