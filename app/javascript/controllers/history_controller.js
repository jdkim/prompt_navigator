import { Controller } from "@hotwired/stimulus"

// Draw arrows connecting child cards to their parent card vertically.
export default class extends Controller {
    static targets = ["svg", "cards"]

    // Private fields
    #drawArrowsBound
    #markerId = "history-arrow-head"
    // Supplement edges get their own marker because the arrowhead is filled,
    // not stroked — a dash pattern alone would leave the head solid grey.
    #supplementMarkerId = "history-supplement-arrow-head"
    #lineageStroke = "#555"
    #supplementStroke = "#7c3aed"
    #supplementDash = "4 3"
    #startX = 32
    // Supplement arcs run down the RIGHT gutter. Sharing the left one with the
    // lineage arrows made both unreadable as soon as a prompt cited more than
    // one node — several arcs of similar length overlapping in 32px. The two
    // channels now have a side each, which also reinforces that they are
    // different kinds of edge. Keep in step with .history-stack's
    // padding-right in history.css.
    #rightMargin = 32
    // Curve offset scales with the vertical gap so arcs of different lengths
    // nest instead of overlap. Bounded so short arcs don't collapse onto the
    // stack and long arcs don't escape the sidebar pane (the stack only has
    // `padding-left: 32px` of space before the chat area).
    #minCurveOffset = 12
    #maxCurveOffset = 28
    #curveScale = 0.22

    connect() {
        this.#drawArrows()
        this.#scrollActiveCardIntoView()
        this.#drawArrowsBound = this.#drawArrows.bind(this)
        window.addEventListener("resize", this.#drawArrowsBound)
    }

    // If the currently-selected history card would be scrolled off-screen
    // (short viewport, long history), bring it into view. `block: "nearest"`
    // is a no-op when the card is already visible, so this only jumps when
    // needed. Runs on `connect()`, which fires on initial mount AND after
    // Turbo replaces the sidebar (post-stream / branch / rename).
    #scrollActiveCardIntoView() {
        const activeCard = this.element.querySelector(".history-card.is-active")
        if (!activeCard) return
        activeCard.scrollIntoView({ block: "nearest", inline: "nearest" })
    }

    disconnect() {
        window.removeEventListener("resize", this.#drawArrowsBound)
    }

    // ================= Private methods =================
    #drawArrows() {
        // Skip if svg target is missing (template variant without arrow canvas)
        if (!this.hasSvgTarget) return
        const svg = this.svgTarget

        this.#clearSvg(svg)
        const cardMap = this.#buildCardMap()
        const bbox = this.#setupSvgDimensions(svg)

        this.#ensureArrowMarker(svg, this.#markerId, this.#lineageStroke)
        this.#ensureArrowMarker(svg, this.#supplementMarkerId, this.#supplementStroke)

        // Iterate over Stimulus targets instead of querySelectorAll
        for (const card of this.cardsTargets) {
            this.#drawArrowForCard(card, cardMap, bbox, svg)
            this.#drawSupplementArrows(card, cardMap, bbox, svg)
        }
    }

    #clearSvg(svg) {
        svg.replaceChildren()
    }

    #buildCardMap() {
        const cardMap = new Map()
        for (const c of this.cardsTargets) {
            cardMap.set(c.dataset.uuid, c)
        }
        return cardMap
    }

    #setupSvgDimensions(svg) {
        const bbox = this.element.getBoundingClientRect()
        svg.setAttribute("width", bbox.width)
        svg.setAttribute("height", bbox.height)
        svg.setAttribute("viewBox", `0 0 ${bbox.width} ${bbox.height}`)
        return bbox
    }

    #ensureArrowMarker(svg, id, fill) {
        if (svg.querySelector(`#${id}`)) return

        const marker = document.createElementNS(
            "http://www.w3.org/2000/svg",
            "marker"
        )
        marker.setAttribute("id", id)
        marker.setAttribute("markerWidth", "6")
        marker.setAttribute("markerHeight", "6")
        marker.setAttribute("refX", "5")
        marker.setAttribute("refY", "3")
        marker.setAttribute("orient", "auto")

        const arrowPath = document.createElementNS(
            "http://www.w3.org/2000/svg",
            "path"
        )
        arrowPath.setAttribute("d", "M0,0 L6,3 L0,6 Z")
        arrowPath.setAttribute("fill", fill)
        marker.appendChild(arrowPath)

        // Reuse one <defs> so the second marker doesn't add a duplicate node.
        let defs = svg.querySelector("defs")
        if (!defs) {
            defs = document.createElementNS("http://www.w3.org/2000/svg", "defs")
            svg.appendChild(defs)
        }
        defs.appendChild(marker)
    }

    #drawArrowForCard(card, cardMap, bbox, svg) {
        const parentUuid = card.dataset.parentUuid
        if (!parentUuid) return

        const parentCard = cardMap.get(parentUuid)
        if (!parentCard) return

        const childRect = card.getBoundingClientRect()
        const parentRect = parentCard.getBoundingClientRect()

        const startY = parentRect.top + parentRect.height / 2 - bbox.top
        const endY = childRect.top + childRect.height / 2 - bbox.top
        const verticalGap = Math.abs(endY - startY)

        // Skip if cards are adjacent - straight arrow is rendered by helper
        if (verticalGap < 80) return

        const path = this.#createCurvedArrowPath(startY, endY, verticalGap)
        svg.appendChild(path)
    }

    // Supplement edges: nodes whose content is attached to this prompt as
    // reference material rather than entering as dialogue. Drawn dotted and in
    // a distinct colour so the two channels are told apart at a glance.
    //
    // Unlike the lineage arrow above there is NO short-gap bail-out. That
    // shortcut exists because the template draws a straight ↑/↓ between
    // adjacent parent/child cards; nothing does that for supplements, so
    // skipping short gaps would silently drop the arrow entirely.
    #drawSupplementArrows(card, cardMap, bbox, svg) {
        const raw = card.dataset.supplementUuids
        if (!raw) return

        const childRect = card.getBoundingClientRect()
        const endY = childRect.top + childRect.height / 2 - bbox.top

        for (const uuid of raw.split(",")) {
            const sourceCard = cardMap.get(uuid.trim())
            if (!sourceCard) continue

            const sourceRect = sourceCard.getBoundingClientRect()
            const startY = sourceRect.top + sourceRect.height / 2 - bbox.top
            const verticalGap = Math.abs(endY - startY)

            const path = this.#createCurvedArrowPath(startY, endY, verticalGap, {
                stroke: this.#supplementStroke,
                dash: this.#supplementDash,
                markerId: this.#supplementMarkerId,
                x: bbox.width - this.#rightMargin,
                direction: 1
            })
            svg.appendChild(path)
        }
    }

    #createCurvedArrowPath(startY, endY, verticalGap, options = {}) {
        const startX = options.x ?? this.#startX
        // -1 bows outward to the left (lineage), +1 to the right (supplements).
        const direction = options.direction ?? -1
        const curveOffset = Math.max(
            this.#minCurveOffset,
            Math.min(verticalGap * this.#curveScale, this.#maxCurveOffset)
        )
        const curveX = startX + direction * curveOffset
        const pathData = `M ${startX} ${startY} C ${curveX} ${startY}, ${curveX} ${endY}, ${startX} ${endY}`

        const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
        path.setAttribute("d", pathData)
        path.setAttribute("fill", "none")
        path.setAttribute("stroke", options.stroke || this.#lineageStroke)
        path.setAttribute("stroke-width", "1.2")
        if (options.dash) path.setAttribute("stroke-dasharray", options.dash)
        path.setAttribute("marker-end", `url(#${options.markerId || this.#markerId})`)

        return path
    }
}
