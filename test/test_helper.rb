# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require_relative "../test/dummy/config/environment"
ActiveRecord::Migrator.migrations_paths = [ File.expand_path("../test/dummy/db/migrate", __dir__) ]
ActiveRecord::Migrator.migrations_paths << File.expand_path("../db/migrate", __dir__)
require "rails/test_help"

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
  ActiveSupport::TestCase.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
  ActionDispatch::IntegrationTest.fixture_paths = ActiveSupport::TestCase.fixture_paths
  ActiveSupport::TestCase.file_fixture_path = File.expand_path("fixtures", __dir__) + "/files"
  ActiveSupport::TestCase.fixtures :all
end

# Schema for the dummy app's SQLite DB, mirroring the generator's migration
# templates. Kept inline so the dummy app doesn't need its own migrations
# directory checked into the gem.
#
# Everything below is declared with `if_not_exists:` rather than wrapped in a
# coarse `unless table_exists?` guard. That guard skipped the whole block once
# the table existed, so a newly added column never reached the *persisted*
# test.sqlite3 and every test failed with an undefined-method error that
# pointed at the model rather than at the stale database. Per-object checks
# mean a schema addition here just works, on an existing DB or a fresh one.
ActiveRecord::Schema.define do
  create_table :prompt_navigator_prompt_executions, if_not_exists: true do |t|
    t.references :previous,
                 foreign_key: { to_table: :prompt_navigator_prompt_executions },
                 index: true, null: true
    t.string :execution_id
    t.text :prompt
    t.string :llm_platform
    t.string :model
    t.string :configuration
    t.text :response
    t.timestamps
  end

  create_table :prompt_navigator_supplements, if_not_exists: true do |t|
    t.references :prompt_execution,
                 foreign_key: { to_table: :prompt_navigator_prompt_executions },
                 null: false, index: { name: "idx_pn_supplements_on_execution" }
    t.references :supplement_execution,
                 foreign_key: { to_table: :prompt_navigator_prompt_executions },
                 null: false, index: { name: "idx_pn_supplements_on_supplement" }
    t.integer :position, null: false, default: 0
    t.timestamps
    t.index [ :prompt_execution_id, :supplement_execution_id ],
            unique: true, name: "idx_pn_supplements_pair"
  end
end
