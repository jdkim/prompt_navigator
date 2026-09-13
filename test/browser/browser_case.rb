require "test_helper"
require "rack"
require "puma"
require "selenium-webdriver"
require "tmpdir"

# Base for tests that need a real browser.
#
# history_controller.js draws SVG paths from live DOM geometry — element
# positions, vertical gaps, the width of the stack — so none of it can be
# exercised without laying the page out for real. Everything else in this gem
# is testable without a browser; this exists only for the arrows.
#
# The page is served over HTTP rather than file://, because ES modules from a
# file:// origin are treated as opaque and refused, and the failure is silent:
# the module never runs and the SVG simply stays empty.
class BrowserCase < ActiveSupport::TestCase
  # Stand-in for @hotwired/stimulus so the real controller runs unmodified.
  # It emulates only what the controller touches — the element and the target
  # accessors Stimulus generates from `static targets`.
  #
  # What this therefore does NOT cover: that Stimulus itself connects the
  # controller, and the asset-pipeline wiring that delivers it. Those are
  # covered where they actually live, in a host app. What it does cover is the
  # drawing, which is the part with real logic in it.
  STIMULUS_SHIM = <<~JS
    export class Controller {
      constructor(element) { this.element = element }
      get svgTarget()    { return this.element.querySelector('[data-history-target="svg"]') }
      get hasSvgTarget() { return !!this.svgTarget }
      get cardsTargets() { return [...this.element.querySelectorAll('[data-history-target="cards"]')] }
    }
  JS

  class << self
    attr_accessor :server, :port, :docroot
  end

  def self.boot!
    return if server

    # Under the project, not Dir.mktmpdir. A snap-confined Chromium — which is
    # what a Linux desktop is likely to have — cannot read or write /tmp, and
    # the failure is a silent 120s Net::ReadTimeout per test with nothing in it
    # naming the cause. Anywhere inside $HOME that is not a dotted path works
    # under confinement, and is harmless on an unconfined browser.
    self.docroot = File.expand_path("../../tmp/browser-tests-#{Process.pid}", __dir__)
    FileUtils.mkdir_p(docroot)
    app = Rack::Files.new(docroot)
    self.server = Puma::Server.new(app, Puma::Events.new)
    self.port = server.add_tcp_listener("127.0.0.1", 0).addr[1]
    server.run
    at_exit { server&.stop(true); FileUtils.rm_rf(docroot) }
  end

  def setup
    self.class.boot!
    skip_unless_browser
  end

  # Serve `body` as a page that loads the real controller, then return a driver
  # with it open.
  def render(body)
    root = self.class.docroot
    FileUtils.cp(File.expand_path("../../app/javascript/controllers/history_controller.js", __dir__), root)
    FileUtils.cp(File.expand_path("../../app/assets/stylesheets/prompt_navigator/history.css", __dir__), root)
    File.write(File.join(root, "stimulus-shim.js"), STIMULUS_SHIM)
    File.write(File.join(root, "index.html"), page(body))

    driver.navigate.to "http://127.0.0.1:#{self.class.port}/index.html"
    # The module runs on load; wait for it rather than assuming.
    Selenium::WebDriver::Wait.new(timeout: 5).until { driver.execute_script("return window.__drawn === true") }
    driver
  end

  def page(body)
    <<~HTML
      <html><head><meta charset="utf-8">
      <script type="importmap">{ "imports": { "@hotwired/stimulus": "./stimulus-shim.js" } }</script>
      <link rel="stylesheet" href="history.css">
      <style>body{margin:0;padding:12px;width:400px;font-family:sans-serif}
             .history-card-prompt{font-size:12px}</style>
      </head><body>
      #{body}
      <script type="module">
        import C from "./history_controller.js"
        new C(document.getElementById("stack")).connect()
        window.__drawn = true
      </script>
      </body></html>
    HTML
  end

  # Every drawn arrow, as { d:, stroke:, dashed:, marker: }.
  def arrows
    driver.execute_script(<<~JS)
      return [...document.querySelectorAll('svg.history-arrows > path')].map((p) => ({
        d: p.getAttribute("d"),
        stroke: p.getAttribute("stroke"),
        dashed: !!p.getAttribute("stroke-dasharray"),
        marker: p.getAttribute("marker-end")
      }))
    JS
  end

  # The x the arc starts and ends at — which gutter it runs down.
  def anchor_x(arrow)
    arrow["d"][/\AM ([\d.]+)/, 1].to_f
  end

  # The control-point x — which way it bows.
  def control_x(arrow)
    arrow["d"][/C ([\d.-]+)/, 1].to_f
  end

  def stack_width
    driver.execute_script("return document.getElementById('stack').getBoundingClientRect().width")
  end

  def card(uuid, parent: nil, supplements: nil, text: uuid)
    attrs = %(data-history-target="cards" data-uuid="#{uuid}")
    attrs += %( data-parent-uuid="#{parent}") if parent
    attrs += %( data-supplement-uuids="#{supplements}") if supplements
    %(<div class="history-card" #{attrs}><div class="history-card-row">) +
      %(<a class="history-card-link" href="#"><div class="history-card-prompt">#{text}</div></a>) +
      %(</div></div>)
  end

  def stack(*cards)
    %(<div class="history-stack" id="stack">#{cards.join}) +
      %(<svg class="history-arrows" data-history-target="svg"></svg></div>)
  end

  # Tall spacer so a pair is separated by more than the 80px adjacency
  # threshold, forcing a curved arrow instead of the template's straight one.
  def gap
    %(<div style="height:120px"></div>)
  end

  private

  def driver
    @driver ||= begin
      opts = Selenium::WebDriver::Chrome::Options.new
      profile = File.join(self.class.docroot, "profile-#{Process.pid}")
      FileUtils.mkdir_p(profile)
      %W[--headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage
         --user-data-dir=#{profile}].each { |a| opts.add_argument(a) }
      Selenium::WebDriver.for(:chrome, options: opts)
    end
  end

  def skip_unless_browser
    driver
  rescue StandardError => e
    skip "no usable browser: #{e.class}"
  end

  def teardown
    @driver&.quit
    @driver = nil
  end
end
