require "date"
require "digest"
require "json"
require "net/http"
require "uri"
require "yaml"

# Creates or updates the app's in-app purchases and subscriptions in App Store
# Connect from Config/Tinytide.storekit, the file Xcode already uses to test
# purchases. Run it through `bundle exec fastlane upload_iap` (see
# fastlane/README.md); `dry_run:true` reads App Store Connect and prints what
# would change without changing anything.
#
# Safe to run again and again: whatever already matches is left alone. It
# never deletes anything, and it doesn't change the price of a subscription
# that is already on sale.
module AppStoreIAP
  NAME_LIMIT = 30
  DESCRIPTION_LIMIT = 45

  TYPES = {
    "Consumable" => "CONSUMABLE",
    "NonConsumable" => "NON_CONSUMABLE",
    "NonRenewingSubscription" => "NON_RENEWING_SUBSCRIPTION"
  }.freeze
  PERIODS = {
    "P1W" => "ONE_WEEK", "P1M" => "ONE_MONTH", "P2M" => "TWO_MONTHS",
    "P3M" => "THREE_MONTHS", "P6M" => "SIX_MONTHS", "P1Y" => "ONE_YEAR"
  }.freeze

  Localization = Struct.new(:locale, :name, :description, keyword_init: true)
  Product = Struct.new(:product_id, :reference_name, :type, :price, :family_sharable,
                       :localizations, :review_note, :review_screenshot, keyword_init: true)
  Subscription = Struct.new(:product_id, :reference_name, :period, :group_level, :price, :family_sharable,
                            :localizations, :review_note, :review_screenshot, keyword_init: true)
  Group = Struct.new(:reference_name, :localizations, :subscriptions, keyword_init: true)

  class Error < StandardError; end

  # MARK: - What should be on App Store Connect

  # The StoreKit file plus fastlane/in_app_purchases.yml, in App Store Connect's terms.
  class Catalog
    attr_reader :products, :groups, :territory, :problems

    def self.load(root)
      new(
        storekit: JSON.parse(File.read(File.join(root, "Config", "Tinytide.storekit"))),
        config: YAML.safe_load(File.read(File.join(root, "fastlane", "in_app_purchases.yml"))) || {},
        locales: Dir.children(File.join(root, "fastlane", "metadata"))
                    .select { |name| File.directory?(File.join(root, "fastlane", "metadata", name)) }
                    .reject { |name| name == "review_information" },
        screenshot_dir: File.join(root, "fastlane", "in_app_purchases")
      )
    end

    # locales: the App Store languages (fastlane/metadata folder names).
    def initialize(storekit:, config:, locales:, screenshot_dir:)
      @locales = locales.sort
      @review = config.fetch("review", {}) || {}
      @screenshot_dir = screenshot_dir
      @problems = []
      @territory = storekit.dig("settings", "_storefront") || "USA"

      @products = (storekit["products"] || []).map do |p|
        type = TYPES[p["type"]] or problem("#{p['productID']}: unknown product type #{p['type'].inspect}")
        Product.new(
          product_id: p["productID"], reference_name: p["referenceName"], type: type,
          price: p["displayPrice"], family_sharable: p["familyShareable"] == true,
          localizations: localizations(p["productID"], p["localizations"]), **review(p["productID"])
        )
      end
      @groups = (storekit["subscriptionGroups"] || []).map do |g|
        Group.new(
          reference_name: g["name"],
          localizations: localizations(g["name"], g["localizations"], description: false),
          subscriptions: (g["subscriptions"] || []).map do |s|
            period = PERIODS[s["recurringSubscriptionPeriod"]] or
              problem("#{s['productID']}: unsupported period #{s['recurringSubscriptionPeriod'].inspect}")
            Subscription.new(
              product_id: s["productID"], reference_name: s["referenceName"], period: period,
              group_level: s["groupNumber"], price: s["displayPrice"],
              family_sharable: s["familyShareable"] == true,
              localizations: localizations(s["productID"], s["localizations"]), **review(s["productID"])
            )
          end
        )
      end
      problem("#{(storekit['nonRenewingSubscriptions'] || []).size} non-renewing subscriptions aren't supported yet") unless (storekit["nonRenewingSubscriptions"] || []).empty?
    end

    # StoreKit writes en_US, fr, zh_Hans; App Store Connect wants en-US, fr-FR, zh-Hans.
    def asc_locale(storekit_locale)
      code = storekit_locale.tr("_", "-")
      return code if @locales.include?(code)
      matches = @locales.select { |l| l.start_with?("#{code}-") }
      matches.size == 1 ? matches.first : nil
    end

    private

    def problem(message)
      @problems << message
      nil
    end

    def localizations(owner, list, description: true)
      found = (list || []).filter_map do |l|
        locale = asc_locale(l["locale"])
        next problem("#{owner}: StoreKit locale #{l['locale']} matches no App Store language in fastlane/metadata") unless locale
        name = l["displayName"].to_s.strip
        text = description ? l["description"].to_s.strip : nil
        problem("#{owner} #{locale}: display name is empty") if name.empty?
        problem("#{owner} #{locale}: display name is #{name.length} characters, the limit is #{NAME_LIMIT}") if name.length > NAME_LIMIT
        if description
          problem("#{owner} #{locale}: description is empty") if text.empty?
          problem("#{owner} #{locale}: description is #{text.length} characters, the limit is #{DESCRIPTION_LIMIT}") if text.length > DESCRIPTION_LIMIT
        end
        Localization.new(locale: locale, name: name, description: text)
      end
      missing = @locales - found.map(&:locale)
      problem("#{owner}: no text for #{missing.join(', ')}") unless missing.empty?
      found
    end

    def review(product_id)
      _, entry = @review.find { |pattern, _| File.fnmatch(pattern, product_id) }
      return { review_note: nil, review_screenshot: nil } unless entry
      file = entry["screenshot"] && File.join(@screenshot_dir, entry["screenshot"])
      { review_note: entry["note"]&.strip, review_screenshot: file }
    end
  end

  # MARK: - App Store Connect API

  class NotFound < Error; end

  # A list endpoint's resources from every page, plus whatever they included.
  Page = Struct.new(:data, :included) do
    def find_included(type, id)
      included.find { |r| r["type"] == type && r["id"] == id }
    end
  end

  # Talks to the App Store Connect API with the key in asc_api_key.json.
  class Client
    HOST = "https://api.appstoreconnect.apple.com".freeze

    def initialize(api_key_path)
      require "spaceship"
      raise Error, "No API key at #{api_key_path} (see fastlane/README.md)" unless File.exist?(api_key_path)
      @token = Spaceship::ConnectAPI::Token.from_json_file(api_key_path)
    end

    def get(path, params = {})
      request("GET", path, params: params)
    end

    def get_all(path, params = {})
      page = Page.new([], [])
      body = get(path, params)
      loop do
        page.data.concat(Array(body["data"]))
        page.included.concat(Array(body["included"]))
        next_url = body.dig("links", "next")
        break unless next_url
        body = request("GET", next_url)
      end
      page
    end

    def post(path, body)
      request("POST", path, body: body)
    end

    def patch(path, body)
      request("PATCH", path, body: body)
    end

    def delete(path)
      request("DELETE", path)
    end

    # Sends one part of a file to where App Store Connect asked for it.
    def upload(operation, bytes)
      uri = URI(operation["url"])
      req = Net::HTTPGenericRequest.new(operation["method"], true, true, uri.request_uri)
      Array(operation["requestHeaders"]).each { |h| req[h["name"]] = h["value"] }
      req.body = bytes
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
      raise Error, "Upload failed: HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
    end

    private

    def request(method, path, params: {}, body: nil, attempt: 1)
      uri = URI(path.match?(%r{\Ahttps?://}) ? path : HOST + path)
      uri.query = URI.encode_www_form(params) unless params.empty?
      @token.refresh! if @token.expiration - Time.now < 60

      req = Net::HTTPGenericRequest.new(method, !body.nil?, true, uri.request_uri)
      req["Authorization"] = "Bearer #{@token.text}"
      if body
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      end
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }

      code = res.code.to_i
      return res.body.to_s.empty? ? {} : JSON.parse(res.body) if (200..299).cover?(code)
      if (code == 429 || code >= 500) && attempt < 5
        sleep(2**attempt)
        return request(method, path, params: params, body: body, attempt: attempt + 1)
      end
      raise NotFound, "#{method} #{uri.path}: not found" if code == 404
      raise Error, "#{method} #{uri.path}: HTTP #{code} #{error_detail(res.body)}"
    end

    def error_detail(body)
      errors = JSON.parse(body.to_s)["errors"] || []
      errors.map { |e| [e["title"], e["detail"]].compact.join(": ") }.join("; ")
    rescue JSON::ParserError
      body.to_s[0, 300]
    end
  end

  # MARK: - Bringing App Store Connect in line

  # Per kind of localized resource, where its text lives. Text belongs to a
  # version (like an app version); an approved version is locked, so changing
  # it means starting a new version that goes through App Review again.
  # Resources from before versions existed keep their text on themselves.
  LOCALIZED = {
    iap: {
      versions: "/v2/inAppPurchases/%s/versions", version_type: "inAppPurchaseVersions",
      parent: %w[inAppPurchase inAppPurchases], version_localizations: "/v1/inAppPurchaseVersions/%s/localizations",
      legacy_list: "/v2/inAppPurchases/%s/inAppPurchaseLocalizations", legacy_parent: %w[inAppPurchaseV2 inAppPurchases],
      type: "inAppPurchaseLocalizations", v1: "/v1/inAppPurchaseLocalizations", v2: "/v2/inAppPurchaseLocalizations",
      fields: %w[name description]
    },
    subscription: {
      versions: "/v1/subscriptions/%s/versions", version_type: "subscriptionVersions",
      parent: %w[subscription subscriptions], version_localizations: "/v1/subscriptionVersions/%s/localizations",
      legacy_list: "/v1/subscriptions/%s/subscriptionLocalizations", legacy_parent: %w[subscription subscriptions],
      type: "subscriptionLocalizations", v1: "/v1/subscriptionLocalizations", v2: "/v2/subscriptionLocalizations",
      fields: %w[name description]
    },
    group: {
      versions: "/v1/subscriptionGroups/%s/versions", version_type: "subscriptionGroupVersions",
      parent: %w[subscriptionGroup subscriptionGroups], version_localizations: "/v1/subscriptionGroupVersions/%s/localizations",
      legacy_list: "/v1/subscriptionGroups/%s/subscriptionGroupLocalizations", legacy_parent: %w[subscriptionGroup subscriptionGroups],
      type: "subscriptionGroupLocalizations", v1: "/v1/subscriptionGroupLocalizations", v2: "/v2/subscriptionGroupLocalizations",
      fields: %w[name]
    }
  }.freeze

  EDITABLE_STATES = %w[PREPARE_FOR_SUBMISSION READY_FOR_REVIEW REJECTED DEVELOPER_REJECTED].freeze
  IN_REVIEW_STATES = %w[WAITING_FOR_REVIEW IN_REVIEW ACCEPTED].freeze
  ON_SALE_STATES = %w[APPROVED DEVELOPER_REMOVED_FROM_SALE REMOVED_FROM_SALE].freeze

  class Sync
    attr_reader :todos, :failures

    def initialize(client:, catalog:, bundle_id:, dry_run: false, out: $stdout)
      @client = client
      @catalog = catalog
      @bundle_id = bundle_id
      @dry_run = dry_run
      @out = out
      @todos = []
      @failures = []
    end

    # True when everything is (or, in a dry run, would be) in line.
    def run
      unless @catalog.problems.empty?
        @catalog.problems.each { |p| say("  ! #{p}") }
        raise Error, "Fix Config/Tinytide.storekit or fastlane/in_app_purchases.yml first"
      end
      app = @client.get_all("/v1/apps", "filter[bundleId]" => @bundle_id).data.find { |a| a.dig("attributes", "bundleId") == @bundle_id }
      raise Error, "No app with bundle ID #{@bundle_id} in App Store Connect; create the app record first" unless app
      @app_id = app["id"]
      say("#{app.dig('attributes', 'name')} (#{@bundle_id})#{@dry_run ? ' - dry run, nothing will be changed' : ''}")

      existing = @client.get_all("/v1/apps/#{@app_id}/inAppPurchasesV2", "limit" => 200).data
      @catalog.products.each do |product|
        guarded(product.product_id) { sync_product(product, existing.find { |r| r.dig("attributes", "productId") == product.product_id }) }
      end

      groups = @client.get_all("/v1/apps/#{@app_id}/subscriptionGroups", "limit" => 200).data
      subscriptions = groups.to_h { |g| [g["id"], @client.get_all("/v1/subscriptionGroups/#{g['id']}/subscriptions", "limit" => 200).data] }
      @catalog.groups.each do |group|
        guarded(group.reference_name) { sync_group(group, groups, subscriptions) }
      end

      say("")
      @todos.uniq.each { |t| say("To do: #{t}") }
      @failures.each { |f| say("Failed: #{f}") }
      say(@failures.empty? ? "Done." : "Finished with #{@failures.size} failure(s).")
      @failures.empty?
    end

    private

    def say(line)
      @out.puts(line)
    end

    def change(line)
      say("  #{@dry_run ? 'would ' : ''}#{line}")
    end

    def guarded(label)
      yield
    rescue Error => e
      say("  ! #{e.message}")
      @failures << "#{label}: #{e.message}"
    end

    def rel(name, type, id)
      { name => { data: { type: type, id: id } } }
    end

    def get_or_nil(path, params = {})
      @client.get(path, params)["data"]
    rescue NotFound
      nil
    end

    # MARK: One-time purchases

    def sync_product(product, remote)
      say("")
      say("#{product.product_id} (#{product.type.downcase.tr('_', '-')}, #{product.reference_name})")
      unless remote
        next_steps(product)
        return if @dry_run
        remote = @client.post("/v2/inAppPurchases", data: {
          type: "inAppPurchases",
          attributes: { name: product.reference_name, productId: product.product_id, inAppPurchaseType: product.type,
                        reviewNote: product.review_note, familySharable: product.family_sharable }.compact,
          relationships: rel(:app, "apps", @app_id)
        })["data"]
      else
        update_attributes("/v2/inAppPurchases", "inAppPurchases", remote,
                          "name" => product.reference_name, "reviewNote" => product.review_note,
                          "familySharable" => product.family_sharable)
      end
      id = remote["id"]
      sync_localizations(:iap, id, product.localizations)
      sync_iap_price(id, product.price)
      sync_iap_availability(id)
      sync_review_screenshot(:iap, id, product.review_screenshot)
    end

    def sync_iap_price(id, price)
      current = current_iap_price(id)
      return say("  price: #{money(price)}") if same_price?(current, price)
      change("set the price: #{current ? money(current) : 'none'} -> #{money(price)} (other countries follow automatically)")
      return if @dry_run
      point = price_point("/v2/inAppPurchases/#{id}/pricePoints", price)
      @client.post("/v1/inAppPurchasePriceSchedules",
                   data: {
                     type: "inAppPurchasePriceSchedules",
                     relationships: {
                       **rel(:inAppPurchase, "inAppPurchases", id),
                       **rel(:baseTerritory, "territories", @catalog.territory),
                       manualPrices: { data: [{ type: "inAppPurchasePrices", id: "${price}" }] }
                     }
                   },
                   included: [{
                     type: "inAppPurchasePrices", id: "${price}", attributes: { startDate: nil },
                     relationships: { **rel(:inAppPurchaseV2, "inAppPurchases", id),
                                      **rel(:inAppPurchasePricePoint, "inAppPurchasePricePoints", point["id"]) }
                   }])
    end

    def current_iap_price(id)
      schedule = get_or_nil("/v2/inAppPurchases/#{id}/iapPriceSchedule")
      return nil unless schedule
      page = @client.get_all("/v1/inAppPurchasePriceSchedules/#{schedule['id']}/manualPrices",
                             "filter[territory]" => @catalog.territory, "include" => "inAppPurchasePricePoint", "limit" => 200)
      price = current(page.data)
      point_id = price&.dig("relationships", "inAppPurchasePricePoint", "data", "id")
      point_id && page.find_included("inAppPurchasePricePoints", point_id)&.dig("attributes", "customerPrice")
    end

    def sync_iap_availability(id)
      return say("  availability: set") if get_or_nil("/v2/inAppPurchases/#{id}/inAppPurchaseAvailability")
      change("make it available in all #{territories.size} territories")
      return if @dry_run
      @client.post("/v1/inAppPurchaseAvailabilities", data: {
        type: "inAppPurchaseAvailabilities",
        attributes: { availableInNewTerritories: true },
        relationships: { **rel(:inAppPurchase, "inAppPurchases", id),
                         availableTerritories: { data: territories.map { |t| { type: "territories", id: t } } } }
      })
    end

    # MARK: Subscriptions

    def sync_group(group, remote_groups, remote_subscriptions)
      say("")
      say("Subscription group \"#{group.reference_name}\"")
      ids = group.subscriptions.map(&:product_id)
      remote = remote_groups.find { |g| g.dig("attributes", "referenceName") == group.reference_name } ||
               remote_groups.find { |g| remote_subscriptions[g["id"]].any? { |s| ids.include?(s.dig("attributes", "productId")) } }
      if remote
        update_attributes("/v1/subscriptionGroups", "subscriptionGroups", remote, "referenceName" => group.reference_name)
      else
        change("create it, with its name in #{group.localizations.size} languages")
        unless @dry_run
          remote = @client.post("/v1/subscriptionGroups", data: {
            type: "subscriptionGroups", attributes: { referenceName: group.reference_name },
            relationships: rel(:app, "apps", @app_id)
          })["data"]
        end
      end
      sync_localizations(:group, remote["id"], group.localizations) if remote

      group.subscriptions.each do |subscription|
        guarded(subscription.product_id) do
          match = remote_subscriptions.values.flatten.find { |s| s.dig("attributes", "productId") == subscription.product_id }
          if match && remote && !remote_subscriptions.fetch(remote["id"], []).include?(match)
            raise Error, "#{subscription.product_id} is in a different subscription group in App Store Connect; move it there by hand"
          end
          sync_subscription(subscription, match, remote&.dig("id"))
        end
      end
    end

    def sync_subscription(subscription, remote, group_id)
      say("")
      say("#{subscription.product_id} (#{subscription.period.downcase.tr('_', ' ')} subscription, #{subscription.reference_name})")
      unless remote
        next_steps(subscription)
        return if @dry_run
        remote = @client.post("/v1/subscriptions", data: {
          type: "subscriptions",
          attributes: { name: subscription.reference_name, productId: subscription.product_id,
                        subscriptionPeriod: subscription.period, groupLevel: subscription.group_level,
                        reviewNote: subscription.review_note, familySharable: subscription.family_sharable }.compact,
          relationships: rel(:group, "subscriptionGroups", group_id)
        })["data"]
      else
        update_attributes("/v1/subscriptions", "subscriptions", remote,
                          "name" => subscription.reference_name, "reviewNote" => subscription.review_note,
                          "familySharable" => subscription.family_sharable,
                          "subscriptionPeriod" => subscription.period, "groupLevel" => subscription.group_level)
      end
      id = remote["id"]
      sync_localizations(:subscription, id, subscription.localizations)
      sync_subscription_availability(id)
      sync_subscription_price(id, subscription.price, remote.dig("attributes", "state"))
      sync_review_screenshot(:subscription, id, subscription.review_screenshot)
    end

    def sync_subscription_availability(id)
      plans = @client.get_all("/v1/subscriptions/#{id}/planAvailabilities", "limit" => 200).data
      return say("  availability: set") if plans.any? { |p| p.dig("attributes", "planType") != "MONTHLY" }
      change("make it available in all #{territories.size} territories")
      return if @dry_run
      @client.post("/v1/subscriptionPlanAvailabilities", data: {
        type: "subscriptionPlanAvailabilities",
        attributes: { availableInNewTerritories: true, planType: "UPFRONT" },
        relationships: { **rel(:subscription, "subscriptions", id),
                         availableTerritories: { data: territories.map { |t| { type: "territories", id: t } } } }
      })
    end

    def sync_subscription_price(id, price, state)
      page = @client.get_all("/v1/subscriptions/#{id}/prices",
                             "filter[territory]" => @catalog.territory, "include" => "subscriptionPricePoint", "limit" => 200)
      active = current(page.data.reject { |p| p.dig("attributes", "planType") == "MONTHLY" })
      point_id = active&.dig("relationships", "subscriptionPricePoint", "data", "id")
      now = point_id && page.find_included("subscriptionPricePoints", point_id)&.dig("attributes", "customerPrice")
      return say("  price: #{money(price)}") if same_price?(now, price)
      if now && ON_SALE_STATES.include?(state)
        # Existing subscribers are affected (and may have to agree to an
        # increase), so that is a decision for App Store Connect, not a script.
        raise Error, "the subscription is on sale at #{money(now)}; change its price to #{money(price)} in App Store Connect"
      end
      change("set the price: #{now ? money(now) : 'none'} -> #{money(price)}, with Apple's equivalent in every other territory")
      return if @dry_run
      point = price_point("/v1/subscriptions/#{id}/pricePoints", price)
      equal = @client.get_all("/v1/subscriptionPricePoints/#{point['id']}/equalizations", "include" => "territory", "limit" => 8000).data
      targets = [[@catalog.territory, point["id"]]] +
                equal.filter_map { |p| (t = p.dig("relationships", "territory", "data", "id")) && t != @catalog.territory ? [t, p["id"]] : nil }
      targets.each_with_index do |(territory, point_id), i|
        @client.post("/v1/subscriptionPrices", data: {
          type: "subscriptionPrices",
          attributes: { startDate: nil, preserveCurrentPrice: false },
          relationships: { **rel(:subscription, "subscriptions", id),
                           **rel(:territory, "territories", territory),
                           **rel(:subscriptionPricePoint, "subscriptionPricePoints", point_id) }
        })
        @out.print("    #{i + 1}/#{targets.size} territories\r") if (i % 20).zero? || i == targets.size - 1
      end
      say("")
    end

    # MARK: Shared

    # A new product has no ID to look further with in a dry run, so say
    # everything that would happen; a real run reports each step as it goes.
    def next_steps(product)
      return change("create it") unless @dry_run
      screenshot = product.review_screenshot && File.exist?(product.review_screenshot) ? ", and upload the review screenshot" : ""
      change("create it, with text in #{product.localizations.size} languages, a #{money(product.price)} price " \
             "and every territory#{screenshot}")
      sync_review_screenshot(nil, nil, product.review_screenshot) if screenshot.empty?
    end

    # PATCHes only the attributes that differ. Family Sharing can't be turned
    # off once on, so that one is reported instead.
    def update_attributes(path, type, remote, wanted)
      attrs = remote["attributes"] || {}
      diff = wanted.reject { |k, v| v.nil? || attrs[k] == v }
      if diff["familySharable"] == false
        @todos << "#{attrs['productId']}: Family Sharing is on in App Store Connect and can't be turned off; set familyShareable to true in the StoreKit file"
        diff.delete("familySharable")
      end
      return say("  details: up to date") if diff.empty?
      change("update #{diff.keys.join(', ')}")
      return if @dry_run
      @client.patch("#{path}/#{remote['id']}", data: { type: type, id: remote["id"], attributes: diff })
      remote["attributes"] = attrs.merge(diff)
    end

    def sync_localizations(kind, id, wanted)
      spec = LOCALIZED.fetch(kind)
      target = text_target(spec, id)
      existing = localizations_in(spec, id, target)
      creates, updates = text_changes(spec, wanted, existing)
      extra = existing.map { |l| l.dig("attributes", "locale") } - wanted.map(&:locale)
      say("  text: also in #{extra.sort.join(', ')} (not in the StoreKit file; left as is)") unless extra.empty?
      return say("  text: up to date in #{wanted.size} languages") if creates.empty? && updates.empty?

      summary = []
      summary << "add #{creates.map(&:locale).join(', ')}" unless creates.empty?
      summary << "update #{updates.map { |l, _| l.locale }.join(', ')}" unless updates.empty?
      case target[:mode]
      when :in_review
        raise Error, "text changes (#{summary.join('; ')}) wait until version #{target[:number]} is out of review (#{target[:state]})"
      when :approved
        change("start text version #{target[:number] + 1} (version #{target[:number]} is approved) and #{summary.join('; ')}")
        @todos << "Submit the new text versions for review in App Store Connect (In-App Purchases / Subscriptions)"
        return if @dry_run
        version = @client.post("/v1/#{spec[:version_type]}", data: {
          type: spec[:version_type], relationships: rel(spec[:parent][0], spec[:parent][1], id)
        })["data"]
        target = { mode: :version, id: version["id"] }
        creates, updates = text_changes(spec, wanted, localizations_in(spec, id, target))
      else
        change("change the text: #{summary.join('; ')}")
        return if @dry_run
      end

      creates.each do |l|
        if target[:mode] == :version
          @client.post(spec[:v2], data: { type: spec[:type], attributes: text_attributes(spec, l).merge(locale: l.locale),
                                          relationships: rel(:version, spec[:version_type], target[:id]) })
        else
          @client.post(spec[:v1], data: { type: spec[:type], attributes: text_attributes(spec, l).merge(locale: l.locale),
                                          relationships: rel(spec[:legacy_parent][0], spec[:legacy_parent][1], id) })
        end
      end
      updates.each do |l, remote|
        path = target[:mode] == :version ? spec[:v2] : spec[:v1]
        @client.patch("#{path}/#{remote['id']}", data: { type: spec[:type], id: remote["id"], attributes: text_attributes(spec, l) })
      end
    end

    # Where text changes go: the latest version if it can still be edited,
    # a new version if the latest is approved, or the resource itself when
    # it has no versions.
    def text_target(spec, id)
      versions = begin
        @client.get_all(format(spec[:versions], id), "limit" => 200).data
      rescue NotFound
        []
      end
      latest = versions.max_by { |v| v.dig("attributes", "version").to_i }
      return { mode: :legacy } unless latest
      state = latest.dig("attributes", "state")
      number = latest.dig("attributes", "version").to_i
      return { mode: :version, id: latest["id"] } if EDITABLE_STATES.include?(state)
      return { mode: :in_review, id: latest["id"], number: number, state: state } if IN_REVIEW_STATES.include?(state)
      { mode: :approved, id: latest["id"], number: number, state: state }
    end

    def localizations_in(spec, id, target)
      path = target[:mode] == :legacy ? format(spec[:legacy_list], id) : format(spec[:version_localizations], target[:id])
      @client.get_all(path, "limit" => 200).data
    end

    def text_changes(spec, wanted, existing)
      creates = []
      updates = []
      wanted.each do |l|
        remote = existing.find { |r| r.dig("attributes", "locale") == l.locale }
        if remote.nil?
          creates << l
        elsif text_attributes(spec, l).any? { |k, v| remote.dig("attributes", k.to_s).to_s != v.to_s }
          updates << [l, remote]
        end
      end
      [creates, updates]
    end

    def text_attributes(spec, localization)
      spec[:fields].to_h { |f| [f.to_sym, localization[f.to_sym]] }
    end

    def sync_review_screenshot(kind, id, file)
      unless file && File.exist?(file)
        name = file ? "fastlane/in_app_purchases/#{File.basename(file)}" : "a review screenshot in fastlane/in_app_purchases.yml"
        say("  review screenshot: missing #{name}")
        @todos << "Add #{name} (a screenshot of the purchase screen) and run again"
        return
      end
      type, existing_path, parent = if kind == :iap
                                      ["inAppPurchaseAppStoreReviewScreenshots", "/v2/inAppPurchases/#{id}/appStoreReviewScreenshot", rel(:inAppPurchaseV2, "inAppPurchases", id)]
                                    else
                                      ["subscriptionAppStoreReviewScreenshots", "/v1/subscriptions/#{id}/appStoreReviewScreenshot", rel(:subscription, "subscriptions", id)]
                                    end
      checksum = Digest::MD5.file(file).hexdigest
      existing = get_or_nil(existing_path)
      return say("  review screenshot: up to date") if existing&.dig("attributes", "sourceFileChecksum") == checksum
      change("#{existing ? 'replace' : 'upload'} the review screenshot (#{File.basename(file)})")
      return if @dry_run
      @client.delete("/v1/#{type}/#{existing['id']}") if existing
      bytes = File.binread(file)
      created = @client.post("/v1/#{type}", data: {
        type: type, attributes: { fileName: File.basename(file), fileSize: bytes.bytesize }, relationships: parent
      })["data"]
      Array(created.dig("attributes", "uploadOperations")).each do |op|
        @client.upload(op, bytes.byteslice(op["offset"], op["length"]))
      end
      @client.patch("/v1/#{type}/#{created['id']}", data: {
        type: type, id: created["id"], attributes: { uploaded: true, sourceFileChecksum: checksum }
      })
    end

    def territories
      @territories ||= @client.get_all("/v1/territories", "limit" => 200).data.map { |t| t["id"] }
    end

    def price_point(path, price)
      points = @client.get_all(path, "filter[territory]" => @catalog.territory, "limit" => 8000).data
      points.find { |p| same_price?(p.dig("attributes", "customerPrice"), price) } or
        raise Error, "App Store Connect has no #{money(price)} price in #{@catalog.territory}"
    end

    # The price in effect today: started (or no start date) and not ended.
    def current(prices)
      today = Date.today.iso8601
      prices.select { |p| (p.dig("attributes", "startDate") || "") <= today && (p.dig("attributes", "endDate") || "9999") > today }
            .max_by { |p| p.dig("attributes", "startDate") || "" }
    end

    def same_price?(a, b)
      a && b && a.to_s.to_r == b.to_s.to_r
    end

    def money(price)
      @catalog.territory == "USA" ? "$#{price}" : "#{price} (#{@catalog.territory})"
    end
  end

  # Entry point for the upload_iap lane.
  def self.run(root:, api_key_path:, bundle_id:, dry_run:, out: $stdout)
    Sync.new(client: Client.new(api_key_path), catalog: Catalog.load(root),
             bundle_id: bundle_id, dry_run: dry_run, out: out).run
  end
end
