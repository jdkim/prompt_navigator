require_relative "lib/prompt_navigator/version"

Gem::Specification.new do |spec|
  spec.name        = "prompt_navigator"
  spec.version     = PromptNavigator::VERSION
  spec.authors     = [ "dhq_boiler" ]
  spec.email       = [ "dhq_boiler@live.jp" ]
  spec.homepage    = "https://github.com/jdkim/prompt_manager"
  spec.summary     = "A Rails engine for managing and visualizing LLM prompt execution history."
  spec.description = "PromptNavigator is a Rails engine that provides a visual history stack UI for tracking LLM prompt executions. It includes a self-referencing PromptExecution model for building conversation trees, Stimulus-powered SVG arrow visualization between parent-child history cards, and automatic asset pipeline integration."
  spec.license     = "Apache-2.0"

  spec.required_ruby_version = ">= 3.4.9"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/jdkim/prompt_manager"
  spec.metadata["changelog_uri"] = "https://github.com/jdkim/prompt_manager/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", "~> 8.1", ">= 8.1.2"
end
