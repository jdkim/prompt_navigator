
module PromptNavigator
  module Generators
    class ModelingGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      # Each template is copied separately and renumbered, so a host that
      # already ran an earlier one picks up only what it is missing. Existing
      # migrations are never edited in place for that reason — hosts have
      # already run them.
      def add_migrations
        migration_template "db/migrate/20260129073026_create_prompt_navigator_prompt_executions.rb", "db/migrate/create_prompt_navigator_prompt_executions.rb"
        migration_template "db/migrate/20260913000000_add_prompt_navigator_supplements.rb", "db/migrate/add_prompt_navigator_supplements.rb"
      end
    end
  end
end
