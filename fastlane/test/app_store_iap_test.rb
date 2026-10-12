# Tests for fastlane/lib/app_store_iap.rb against an in-memory App Store
# Connect. Runs in CI; locally: ruby fastlane/test/app_store_iap_test.rb
require "minitest/autorun"
require "stringio"
require "tmpdir"
require_relative "../lib/app_store_iap"
require_relative "fake_app_store_connect"

class AppStoreIAPTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  STOREKIT = JSON.parse(File.read(File.join(ROOT, "Config", "Tinytide.storekit")))
  CONFIG = YAML.safe_load(File.read(File.join(ROOT, "fastlane", "in_app_purchases.yml")))
  LOCALES = %w[de-DE en-US es-ES fr-FR ja ko pt-BR zh-Hans zh-Hant].freeze

  def setup
    @screenshots = Dir.mktmpdir
    File.binwrite(File.join(@screenshots, "tip_jar.png"), "tip jar screenshot")
    File.binwrite(File.join(@screenshots, "supporter.png"), "supporter screenshot")
    @asc = FakeAppStoreConnect.new
  end

  def teardown
    FileUtils.remove_entry(@screenshots)
  end

  def catalog(storekit = STOREKIT)
    AppStoreIAP::Catalog.new(storekit: storekit, config: CONFIG, locales: LOCALES, screenshot_dir: @screenshots)
  end

  # A copy of the StoreKit file, changed by the block.
  def storekit
    copy = JSON.parse(JSON.generate(STOREKIT))
    yield copy
    copy
  end

  def sync(catalog: self.catalog, dry_run: false)
    out = StringIO.new
    ok = AppStoreIAP::Sync.new(client: @asc, catalog: catalog, bundle_id: "app.tinytide.ios", dry_run: dry_run, out: out).run
    [ok, out.string]
  end

  # MARK: Catalog

  def test_storekit_file_is_ready_for_app_store_connect
    c = AppStoreIAP::Catalog.load(ROOT)
    assert_empty c.problems
    assert_equal %w[tinytide.tip.small tinytide.tip.medium tinytide.tip.large], c.products.map(&:product_id)
    assert_equal %w[tinytide.supporter.monthly tinytide.supporter.yearly], c.groups.flat_map(&:subscriptions).map(&:product_id)
    assert_equal "USA", c.territory
    c.products.each do |p|
      assert_equal LOCALES, p.localizations.map(&:locale).sort
      assert_match(/Leave a Tip/, p.review_note)
    end
    assert_equal %w[ONE_MONTH ONE_YEAR], c.groups.first.subscriptions.map(&:period)
  end

  def test_maps_storekit_locales_to_app_store_languages
    c = catalog
    assert_equal "fr-FR", c.asc_locale("fr")
    assert_equal "en-US", c.asc_locale("en_US")
    assert_equal "zh-Hant", c.asc_locale("zh_Hant")
    assert_nil c.asc_locale("it")
  end

  def test_flags_text_over_app_store_limits_and_missing_languages
    c = catalog(storekit do |s|
      s["products"][0]["localizations"][0]["description"] = "x" * 46
      s["products"][1]["localizations"].pop
    end)
    assert(c.problems.any? { |p| p.include?("46 characters, the limit is 45") })
    assert(c.problems.any? { |p| p.include?("tinytide.tip.medium: no text for") })
    assert_raises(AppStoreIAP::Error) { sync(catalog: c) }
    assert_empty @asc.writes
  end

  # MARK: Sync

  def test_creates_everything_and_a_second_run_changes_nothing
    ok, out = sync
    assert ok, out

    iaps = @asc.all("inAppPurchases")
    assert_equal %w[CONSUMABLE] * 3, iaps.map { |r| r["attributes"]["inAppPurchaseType"] }
    iaps.each do |iap|
      version = @asc.all("inAppPurchaseVersions", inAppPurchase: iap["id"]).first
      assert_equal LOCALES, @asc.all("inAppPurchaseLocalizations", version: version["id"]).map { |l| l["attributes"]["locale"] }.sort
      assert_equal 1, @asc.all("inAppPurchasePrices", schedule: iap["id"]).size
      assert_equal FakeAppStoreConnect::TERRITORIES.size, @asc.all("inAppPurchaseAvailabilities", inAppPurchase: iap["id"]).first["rel"]["availableTerritories"].size
    end
    small = iaps.find { |r| r["attributes"]["productId"] == "tinytide.tip.small" }
    assert_equal "inAppPurchase-USA-0.99", @asc.all("inAppPurchasePrices", schedule: small["id"]).first["rel"]["inAppPurchasePricePoint"]

    group = @asc.all("subscriptionGroups").first
    assert_equal "Tinytide Supporter", group["attributes"]["referenceName"]
    subs = @asc.all("subscriptions", group: group["id"])
    assert_equal %w[ONE_MONTH ONE_YEAR], subs.map { |s| s["attributes"]["subscriptionPeriod"] }
    yearly = subs.find { |s| s["attributes"]["productId"] == "tinytide.supporter.yearly" }
    prices = @asc.all("subscriptionPrices", subscription: yearly["id"])
    assert_equal FakeAppStoreConnect::TERRITORIES.sort, prices.map { |p| p["rel"]["territory"] }.sort
    assert(prices.all? { |p| p["rel"]["subscriptionPricePoint"].end_with?("-9.99") })
    assert_equal "UPFRONT", @asc.all("subscriptionPlanAvailabilities", subscription: yearly["id"]).first["attributes"]["planType"]

    # Two parts per screenshot, one screenshot per product.
    assert_equal 10, @asc.uploads.size
    assert(@asc.all("inAppPurchaseAppStoreReviewScreenshots").all? { |s| s["attributes"]["uploaded"] })

    @asc.writes.clear
    ok, out = sync
    assert ok, out
    assert_empty @asc.writes, out
    assert_match(/text: up to date in 9 languages/, out)
  end

  def test_dry_run_reads_but_never_writes
    ok, out = sync(dry_run: true)
    assert ok, out
    assert_empty @asc.writes
    assert_match(/would create it, with text in 9 languages, a \$0\.99 price/, out)

    sync
    @asc.writes.clear
    changed = storekit { |s| s["products"][0]["displayPrice"] = "1.99" }
    ok, out = sync(catalog: catalog(changed), dry_run: true)
    assert ok, out
    assert_empty @asc.writes
    assert_match(/would set the price: \$0\.99 -> \$1\.99/, out)
  end

  def test_products_from_before_text_versions_keep_text_on_themselves
    @asc = FakeAppStoreConnect.new(versions: false)
    ok, out = sync
    assert ok, out
    iap = @asc.all("inAppPurchases").first
    assert_equal 9, @asc.all("inAppPurchaseLocalizations", inAppPurchaseV2: iap["id"]).size
    assert_includes @asc.writes, ["POST", "/v1/inAppPurchaseLocalizations"]
  end

  def test_changes_only_what_differs
    sync
    @asc.writes.clear
    changed = storekit do |s|
      s["products"][0]["localizations"].find { |l| l["locale"] == "de" }["description"] = "Danke für die Nächte."
      s["products"][0]["referenceName"] = "Tip - Coffee"
    end
    ok, out = sync(catalog: catalog(changed))
    assert ok, out
    assert_equal 2, @asc.writes.size, @asc.writes.inspect
    assert_match(/change the text: update de-DE/, out)
    assert_match(/update name/, out)
  end

  def test_text_of_an_approved_product_goes_into_a_new_version
    sync
    @asc.all("inAppPurchaseVersions").each { |v| v["attributes"]["state"] = "APPROVED" }
    @asc.all("inAppPurchaseLocalizations").each { |l| l["attributes"]["locked"] = true }
    @asc.writes.clear

    changed = storekit { |s| s["products"][0]["localizations"][0]["displayName"] = "A big coffee" }
    ok, out = sync(catalog: catalog(changed))
    assert ok, out
    assert_includes @asc.writes, ["POST", "/v1/inAppPurchaseVersions"]
    small = @asc.all("inAppPurchases").find { |r| r["attributes"]["productId"] == "tinytide.tip.small" }
    latest = @asc.all("inAppPurchaseVersions", inAppPurchase: small["id"]).max_by { |v| v["attributes"]["version"] }
    assert_equal 2, latest["attributes"]["version"]
    assert_includes @asc.all("inAppPurchaseLocalizations", version: latest["id"]).map { |l| l["attributes"]["name"] }, "A big coffee"
    assert_match(/To do: Submit the new text versions/, out)
  end

  def test_text_waits_while_a_version_is_in_review
    sync
    @asc.all("inAppPurchaseVersions").each { |v| v["attributes"]["state"] = "WAITING_FOR_REVIEW" }
    changed = storekit { |s| s["products"][0]["localizations"][0]["displayName"] = "A big coffee" }
    ok, out = sync(catalog: catalog(changed))
    refute ok
    assert_match(/wait until version 1 is out of review/, out)
  end

  def test_leaves_the_price_of_a_subscription_on_sale_to_app_store_connect
    sync
    @asc.all("subscriptions").each { |s| s["attributes"]["state"] = "APPROVED" }
    @asc.writes.clear
    changed = storekit { |s| s["subscriptionGroups"][0]["subscriptions"][1]["displayPrice"] = "6.99" }
    ok, out = sync(catalog: catalog(changed))
    refute ok
    assert_match(/on sale at \$9\.99; change its price to \$6\.99 in App Store Connect/, out)
    assert_empty @asc.writes.select { |_, path| path == "/v1/subscriptionPrices" }
  end

  def test_family_sharing_is_never_turned_off
    sync
    @asc.writes.clear
    changed = storekit { |s| s["subscriptionGroups"][0]["subscriptions"][0]["familyShareable"] = false }
    ok, out = sync(catalog: catalog(changed))
    assert ok, out
    assert_empty @asc.writes
    assert_match(/Family Sharing is on in App Store Connect and can't be turned off/, out)
  end

  def test_missing_review_screenshot_is_a_to_do_not_a_failure
    File.delete(File.join(@screenshots, "supporter.png"))
    ok, out = sync
    assert ok, out
    assert_match(%r{To do: Add fastlane/in_app_purchases/supporter.png}, out)
    assert_equal 6, @asc.uploads.size
  end

  def test_replaces_a_changed_review_screenshot
    sync
    @asc.writes.clear
    File.binwrite(File.join(@screenshots, "tip_jar.png"), "a newer tip jar screenshot")
    ok, out = sync
    assert ok, out
    assert_equal 3, @asc.writes.count { |m, path| m == "DELETE" && path.start_with?("/v1/inAppPurchaseAppStoreReviewScreenshots/") }
    assert_match(/replace the review screenshot \(tip_jar.png\)/, out)
  end
end
