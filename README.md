# PromptNavigator

A Rails engine for managing and visualizing LLM prompt execution history. It provides a visual history stack UI with interactive SVG arrow connections between parent-child prompt executions, enabling users to navigate conversation trees.

## Features

- **PromptExecution model** - Self-referencing tree structure for tracking prompt executions with UUID identifiers
- **Visual history stack** - Card-based UI displaying prompt history with parent-child relationships
- **Arrow visualization** - Straight arrows (`↑`) for adjacent cards; curved SVG arrows (via Stimulus) for non-adjacent parent-child connections
- **Active state highlighting** - Blue border and glow effect on the currently selected card
- **Responsive design** - Hover effects with lift animation; arrows redraw on window resize
- **Automatic integration** - Controller concern, view helpers, and assets are auto-registered by the engine
- **Rails generator** - `prompt_navigator:modeling` generator for creating the required migration

## Requirements

- Ruby >= 3.4.9
- Rails >= 8.1.2
- Stimulus ([Hotwire](https://hotwired.dev/))

## Installation

Add this line to your application's Gemfile:

```ruby
gem "prompt_navigator"
```

And then execute:

```bash
$ bundle install
```

Generate the migration for prompt executions:

```bash
$ rails generate prompt_navigator:modeling
$ rails db:migrate
```

This creates the `prompt_navigator_prompt_executions` table with the following columns:

| Column | Type | Description |
|--------|------|-------------|
| `execution_id` | string | Unique identifier (UUID), auto-generated on create |
| `prompt` | text | The prompt text sent to the LLM |
| `llm_platform` | string | The LLM platform (e.g., `"openai"`, `"anthropic"`) |
| `model` | string | The model name (e.g., `"gpt-4"`, `"claude-3"`) |
| `configuration` | string | Model configuration as JSON |
| `response` | text | The LLM response text |
| `previous_id` | integer | Foreign key to the parent execution (for building history tree) |

### Verify installation

Run each of these against your host app after `bin/rails db:migrate`:

```bash
# a) The prompt_navigator_prompt_executions table was created
bin/rails runner 'puts ActiveRecord::Base.connection.table_exists?("prompt_navigator_prompt_executions")'
# → true

# b) The history_list view helper is auto-mounted into ActionView
bin/rails runner 'puts ApplicationController.helpers.respond_to?(:history_list)'
# → true

# c) The HistoryManageable controller concern is auto-included
bin/rails runner 'puts ApplicationController.include?(PromptNavigator::HistoryManageable)'
# → true

# d) UUIDs are auto-generated on create
bin/rails runner 'puts PromptNavigator::PromptExecution.new(prompt: "x", llm_platform: "openai", model: "gpt-4", response: "y").tap(&:save).execution_id'
# → prints a fresh UUID
```

## Usage

### Layout Setup

In your application layout (`app/views/layouts/application.html.erb`), add `<%= yield :head %>` in the `<head>` section to load the engine's stylesheets:

```erb
<head>
  <title>Your App</title>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>

  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>

  <%= yield :head %>
</head>
```

### Controller Setup

The `HistoryManageable` concern is automatically included in all controllers by the engine. It provides three methods:

- `initialize_history(history)` - Sets the `@history` instance variable (converts to array)
- `set_active_message_uuid(uuid)` - Sets the `@active_message_uuid` instance variable
- `push_to_history(new_state)` - Appends a new state to `@history`

```ruby
class MyController < ApplicationController
  def index
    # History must be ordered newest-first for arrow visualization to work correctly
    initialize_history(PromptNavigator::PromptExecution.order(id: :desc))
    set_active_message_uuid(params[:execution_id])
  end

  def create
    new_execution = PromptNavigator::PromptExecution.create(
      prompt: params[:prompt],
      llm_platform: "openai",
      model: "gpt-4",
      configuration: params[:config].to_json,
      response: llm_response,
      previous: @current_execution
    )
    push_to_history(new_execution)
  end
end
```

### Rendering the History Component

The `history_list` helper is automatically available in all views. It renders the history stack:

```erb
<%= history_list(
  ->(execution_id) { my_item_path(execution_id) },
  active_uuid: @active_message_uuid
) %>
```

Parameters:

- `card_path` (first argument) - A Proc/Lambda that takes an `execution_id` and returns a URL path for the card link
- `active_uuid:` - The `execution_id` of the currently active card (highlighted with blue border)

Alternatively, you can render the partial directly:

```erb
<%= render "prompt_navigator/history",
    locals: {
      active_uuid: @active_message_uuid,
      card_path: ->(execution_id) { my_item_path(execution_id) }
    }
%>
```

### PromptExecution Model

The `PromptNavigator::PromptExecution` model stores prompt execution records with a self-referencing association for building conversation trees:

```ruby
# Create an execution
execution = PromptNavigator::PromptExecution.create(
  prompt: "Explain Ruby blocks",
  llm_platform: "openai",
  model: "gpt-4",
  configuration: '{"temperature": 0.7}',
  response: "Ruby blocks are..."
)

# Create a follow-up execution linked to the parent
follow_up = PromptNavigator::PromptExecution.create(
  prompt: "Give me an example",
  llm_platform: "openai",
  model: "gpt-4",
  response: "Here is an example...",
  previous: execution  # Sets previous_id to link as child
)

# Access attributes
execution.execution_id  # => "a1b2c3d4-..." (auto-generated UUID)
execution.previous      # => nil (root execution)
follow_up.previous      # => execution (parent)
```

## Architecture

```
PromptNavigator (Rails Engine)
├── Model
│   └── PromptExecution         # Self-referencing tree model with UUID
├── Controller Concern
│   └── HistoryManageable       # Provides initialize_history, set_active_message_uuid, push_to_history
├── View Helper
│   └── Helpers#history_list    # Renders the history partial
├── Partials
│   ├── _history.html.erb       # Main container with Stimulus controller
│   └── _history_card.html.erb  # Individual card with link and arrow logic
├── JavaScript
│   └── history_controller.js   # Stimulus controller for SVG curved arrows
├── Stylesheets
│   └── history.css             # Modern nested CSS for cards, arrows, hover effects
└── Generator
    └── modeling                # Creates migration for prompt_executions table
```

### Arrow Visualization

The history component uses two types of arrows to show parent-child relationships:

1. **Straight arrows** (`↑`) - Rendered as HTML when a card's parent is the immediately adjacent card below it in the list
2. **Curved SVG arrows** - Drawn by the Stimulus controller (`history_controller.js`) when a card's parent is further away (vertical gap >= 80px). These bezier curves arc to the left of the stack

**Note:** Arrow visualization requires the history to be ordered newest-first (e.g., `order(id: :desc)`). If the history is in ascending order, parent-child adjacency detection will not work correctly.

The Stimulus controller automatically redraws SVG arrows on window resize.

## Troubleshooting

### Styles not loading

Make sure you have `<%= yield :head %>` in your application layout's `<head>` section.

### Arrows not appearing

The arrow visualization requires:
1. Stimulus to be properly configured in your application
2. The `history_controller.js` to be loaded (automatic with the asset pipeline)
3. Parent-child relationships to be set using the `previous` association on PromptExecution records

### History not displaying

Ensure that:
1. `@history` is set in your controller using `initialize_history`
2. PromptExecution records have `execution_id` values (automatically generated on create)
3. The `card_path` callable returns valid paths

## Development

After checking out the repo, run:

```bash
$ bundle install
```

Run the tests:

```bash
$ bin/rails test
```

Run the linter:

```bash
$ bundle exec rubocop
```

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/dhq-boiler/prompt_manager).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
