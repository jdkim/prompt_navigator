require_relative "browser_case"

# The model chip's width, in a real browser.
#
# The chip does not show a short platform word. The host registers
# `model_labels` with the catalog's display names, deliberately, so an
# Ollama-hosted Qwen reads "Qwen3.6 35B" rather than "Ollama" — and those names
# can be long. "Gemini 3.1 Flash Image (Nano Banana 2)" is 38 characters, and in
# production it took the whole card row: the chip does not shrink, the link
# beside it does (`flex: 1; min-width: 0`), so the prompt preview collapsed to
# nothing and the card showed only a model name.
#
# This cannot be asserted from rendered HTML — both elements are present either
# way, and the failure is purely in the widths flexbox hands out. It needs
# layout, so it needs a browser.
class HistoryCardLabelTest < BrowserCase
  LONG  = "Gemini 3.1 Flash Image (Nano Banana 2)"
  SHORT = "Gemini"

  def geometry
    driver.execute_script(<<~JS)
      const row    = document.querySelector(".history-card-row");
      const chip   = document.querySelector(".history-card-platform-label");
      const prompt = document.querySelector(".history-card-prompt");
      return {
        row:       row.getBoundingClientRect().width,
        chip:      chip.getBoundingClientRect().width,
        prompt:    prompt.getBoundingClientRect().width,
        truncated: chip.scrollWidth > chip.clientWidth + 1,
        // `truncated` alone cannot tell an ellipsis from a hard clip: both
        // overflow, and only this says which one the user sees.
        ellipsis:  getComputedStyle(chip).textOverflow,
        wraps:     getComputedStyle(chip).whiteSpace
      };
    JS
  end

  test "a long model label leaves the prompt most of the row" do
    render stack(card("a", text: "draw a lego rabbit holding a carrot", label: LONG))
    g = geometry

    assert g["prompt"] > g["row"] / 2,
           "the prompt got #{g['prompt'].round}px of a #{g['row'].round}px row; the chip took #{g['chip'].round}px"
    assert g["chip"] <= (g["row"] * 0.5) + 1,
           "the chip is #{g['chip'].round}px of a #{g['row'].round}px row — the cap is not holding"
  end

  test "a long label is ellipsised rather than wrapped or clipped silently" do
    render stack(card("a", text: "draw a lego rabbit holding a carrot", label: LONG))
    g = geometry

    assert g["truncated"], "the chip was not truncated at all"
    assert_equal "ellipsis", g["ellipsis"],
                 "the chip is clipped with no ellipsis, so the label just stops mid-word"
    assert_equal "nowrap", g["wraps"],
                 "the chip wraps, which grows the row instead of truncating"
  end

  test "a short label is left alone" do
    render stack(card("a", text: "draw a lego rabbit holding a carrot", label: SHORT))
    g = geometry

    refute g["truncated"], "a short label must not be ellipsised"
    assert g["chip"] < g["row"] / 3, "a short label should take only the width it needs"
  end
end
