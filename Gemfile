source "https://rubygems.org"

# Specify your gem's dependencies in prompt_navigator.gemspec.
gemspec

gem "puma"

gem "sqlite3"

gem "propshaft"

# Drives the arrow-rendering tests. history_controller.js draws SVG from live
# DOM geometry, so there is no way to test it without a real browser.
gem "selenium-webdriver", require: false
gem "rack", require: false

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

# Start debugger with binding.b [https://github.com/ruby/debug]
# gem "debug", ">= 1.0.0"
