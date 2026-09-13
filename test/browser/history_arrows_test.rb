require_relative "browser_case"

# The arrow renderer, exercised in a real browser.
#
# Until now nothing tested it at all: it was verified by eye, from screenshots.
# The logic that matters is easy to break silently — which gutter an arc runs
# down, which pairs get an arc at all, and whether a reference edge is visually
# distinguishable from a lineage edge — and none of it shows up in a rendered
# HTML assertion, because the paths are computed from layout after load.
class HistoryArrowsTest < BrowserCase
  # ----- lineage -----

  test "a distant parent gets a solid arc down the left gutter" do
    render stack(card("root"), gap, card("child", parent: "root"))

    assert_equal 1, arrows.length
    arrow = arrows.first
    assert_equal "#555", arrow["stroke"]
    assert_not arrow["dashed"], "a lineage edge must not be dashed"
    # Left gutter: anchored at the 32px margin, bowing further left.
    assert_in_delta 32, anchor_x(arrow), 1
    assert_operator control_x(arrow), :<, anchor_x(arrow)
  end

  # The template draws a straight ↑/↓ between adjacent cards, so the renderer
  # deliberately skips them. Drawing both would double up.
  test "an adjacent parent gets no arc, leaving it to the straight arrow" do
    render stack(card("root"), card("child", parent: "root"))

    assert_empty arrows
  end

  test "a parent that is not on the page is ignored" do
    render stack(card("child", parent: "missing"))

    assert_empty arrows
  end

  # ----- supplements -----

  test "a citation gets a dashed arc down the right gutter" do
    render stack(card("a"), gap, card("b", supplements: "a"))

    assert_equal 1, arrows.length
    arrow = arrows.first
    assert_equal "#7c3aed", arrow["stroke"]
    assert arrow["dashed"], "a reference edge must be visually distinct from lineage"
    # Right gutter: anchored 32px in from the right edge, bowing further right.
    assert_in_delta stack_width - 32, anchor_x(arrow), 1
    assert_operator control_x(arrow), :>, anchor_x(arrow)
  end

  # The <80px skip exists only because the template covers adjacent *lineage*
  # pairs. Nothing covers adjacent citations, so skipping them would drop the
  # arrow entirely — which is what the first implementation did.
  test "an adjacent citation still gets its arc" do
    render stack(card("a"), card("b", supplements: "a"))

    assert_equal 1, arrows.length
    assert arrows.first["dashed"]
  end

  test "each cited node gets its own arc" do
    render stack(card("a"), card("b"), card("c"), gap, card("d", supplements: "a,b,c"))

    assert_equal 3, arrows.count { |a| a["dashed"] }
  end

  test "a citation naming a node that is not on the page is ignored" do
    render stack(card("a"), gap, card("b", supplements: "a,ghost"))

    assert_equal 1, arrows.length
  end

  test "an empty citation list draws nothing" do
    render stack(card("a"), gap, card("b", supplements: ""))

    assert_empty arrows
  end

  # ----- the two channels together -----

  # The reason the gutters were split: with both kinds sharing the left one,
  # several arcs of similar length overlapped and neither could be followed.
  test "lineage and citations occupy opposite gutters" do
    render stack(card("root"), gap, card("tip", parent: "root", supplements: "root"))

    lineage, reference = arrows.partition { |a| !a["dashed"] }
    assert_equal 1, lineage.length
    assert_equal 1, reference.length
    assert_operator anchor_x(lineage.first), :<, anchor_x(reference.first)
    assert_in_delta 32, anchor_x(lineage.first), 1
    assert_in_delta stack_width - 32, anchor_x(reference.first), 1
  end

  # Filled arrowheads cannot be recoloured by the path's stroke, so the two
  # kinds need separate markers — otherwise a dashed violet arc ends in a grey
  # head.
  test "each kind of arc carries its own arrowhead" do
    render stack(card("root"), gap, card("tip", parent: "root", supplements: "root"))

    markers = arrows.map { |a| a["marker"] }.uniq
    assert_equal 2, markers.length, "lineage and reference heads must differ"
    assert_equal 2, driver.find_elements(css: "svg.history-arrows marker").length
  end

  test "redrawing does not accumulate duplicate arrows" do
    render stack(card("a"), gap, card("b", supplements: "a"))
    before = arrows.length

    driver.execute_script("window.dispatchEvent(new Event('resize'))")
    sleep 0.2

    assert_equal before, arrows.length
  end
end
