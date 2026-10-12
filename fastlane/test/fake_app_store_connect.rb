require "date"
require "json"

# An in-memory stand-in for the parts of the App Store Connect API that
# AppStoreIAP uses, so the sync can be tested without an account.
class FakeAppStoreConnect
  TERRITORIES = %w[USA CAN JPN DEU CHN].freeze
  PRICES = %w[0.99 1.99 2.99 4.99 6.99 9.99].freeze

  attr_reader :writes, :uploads

  def initialize(bundle_id: "app.tinytide.ios", versions: true)
    @versions = versions # whether new products get a text version, as now
    @next_id = 0
    @store = Hash.new { |h, k| h[k] = {} }
    @writes = []
    @uploads = []
    add("apps", { "bundleId" => bundle_id, "name" => "Tinytide" }, {}, id: "app1")
  end

  # MARK: Seeding and inspecting

  def add(type, attributes, relationships = {}, id: nil)
    id ||= "#{type}-#{@next_id += 1}"
    @store[type][id] = { "type" => type, "id" => id, "attributes" => attributes, "rel" => relationships }
    id
  end

  def all(type, **rel)
    @store[type].values.select { |r| rel.all? { |k, v| r["rel"][k.to_s] == v } }
  end

  def attributes(type, id)
    @store[type].fetch(id)["attributes"]
  end

  # MARK: Client interface

  def get(path, params = {})
    route("GET", path, params)
  end

  def get_all(path, params = {})
    body = get(path, params)
    AppStoreIAP::Page.new(Array(body["data"]), Array(body["included"]))
  end

  def post(path, body)
    @writes << ["POST", path]
    route("POST", path, {}, body)
  end

  def patch(path, body)
    @writes << ["PATCH", path]
    route("PATCH", path, {}, body)
  end

  def delete(path)
    @writes << ["DELETE", path]
    type, id = path.split("/")[2..3]
    @store[type].delete(id) or raise AppStoreIAP::NotFound, path
    {}
  end

  def upload(operation, bytes)
    @uploads << [operation["url"], bytes.bytesize]
  end

  private

  def json(record)
    return nil unless record
    rel = record["rel"].transform_values { |id| { "data" => { "id" => id } } }
    { "type" => record["type"], "id" => record["id"], "attributes" => record["attributes"], "relationships" => rel }
  end

  def list(records, included = [])
    { "data" => records.map { |r| json(r) }, "included" => included.map { |r| json(r) } }
  end

  def one(record)
    raise AppStoreIAP::NotFound, "not found" unless record
    { "data" => json(record) }
  end

  def create(body, extra_rel = {})
    data = body["data"]
    rel = (data["relationships"] || {}).transform_values { |v| v["data"].is_a?(Hash) ? v["data"]["id"] : v["data"] }
    id = add(data["type"], data["attributes"] || {}, rel.merge(extra_rel))
    @store[data["type"]][id]
  end

  def update(type, id, body)
    record = @store[type].fetch(id) { raise AppStoreIAP::NotFound, id }
    attributes = body["data"]["attributes"]
    if record["attributes"]["locked"]
      raise AppStoreIAP::Error, "PATCH /#{type}/#{id}: HTTP 409 this text belongs to an approved version"
    end
    record["attributes"].merge!(attributes)
    { "data" => json(record) }
  end

  def points(kind, territory)
    PRICES.map do |price|
      id = "#{kind}-#{territory}-#{price}"
      @store["#{kind}PricePoints"][id] ||= { "type" => "#{kind}PricePoints", "id" => id,
                                             "attributes" => { "customerPrice" => price }, "rel" => { "territory" => territory } }
    end
  end

  def new_version(kind, parent_rel, parent_id)
    add("#{kind}Versions", { "version" => all("#{kind}Versions", parent_rel => parent_id).size + 1,
                             "state" => "PREPARE_FOR_SUBMISSION" }, { parent_rel => parent_id })
  end

  def route(method, path, params, body = nil)
    p = path.sub(%r{\Ahttps://[^/]+}, "")
    body = JSON.parse(JSON.generate(body)) if body
    case [method, p]
    in ["GET", "/v1/apps"]
      list(all("apps").select { |a| a["attributes"]["bundleId"] == params["filter[bundleId]"] })
    in ["GET", "/v1/territories"]
      list(TERRITORIES.map { |t| { "type" => "territories", "id" => t, "attributes" => {}, "rel" => {} } })

    # One-time purchases
    in ["GET", %r{\A/v1/apps/(\w+)/inAppPurchasesV2\z}]
      list(all("inAppPurchases", app: $1))
    in ["POST", "/v2/inAppPurchases"]
      record = create(body)
      new_version("inAppPurchase", "inAppPurchase", record["id"]) if @versions
      { "data" => json(record) }
    in ["PATCH", %r{\A/v2/inAppPurchases/([\w-]+)\z}]
      update("inAppPurchases", $1, body)
    in ["GET", %r{\A/v2/inAppPurchases/([\w-]+)/versions\z}]
      list(all("inAppPurchaseVersions", inAppPurchase: $1))
    in ["POST", "/v1/inAppPurchaseVersions"]
      parent = body["data"]["relationships"]["inAppPurchase"]["data"]["id"]
      { "data" => json(@store["inAppPurchaseVersions"][new_version("inAppPurchase", "inAppPurchase", parent)]) }
    in ["GET", %r{\A/v1/inAppPurchaseVersions/([\w-]+)/localizations\z}]
      list(all("inAppPurchaseLocalizations", version: $1))
    in ["GET", %r{\A/v2/inAppPurchases/([\w-]+)/inAppPurchaseLocalizations\z}]
      list(all("inAppPurchaseLocalizations", inAppPurchaseV2: $1))
    in ["POST", "/v1/inAppPurchaseLocalizations" | "/v2/inAppPurchaseLocalizations"]
      { "data" => json(create(body)) }
    in ["PATCH", %r{\A/v[12]/inAppPurchaseLocalizations/([\w-]+)\z}]
      update("inAppPurchaseLocalizations", $1, body)
    in ["GET", %r{\A/v2/inAppPurchases/([\w-]+)/iapPriceSchedule\z}]
      one(@store["inAppPurchasePriceSchedules"][$1])
    in ["GET", %r{\A/v1/inAppPurchasePriceSchedules/([\w-]+)/manualPrices\z}]
      prices = all("inAppPurchasePrices", schedule: $1).select { |r| r["rel"]["territory"] == params["filter[territory]"] }
      list(prices, prices.map { |r| @store["inAppPurchasePricePoints"][r["rel"]["inAppPurchasePricePoint"]] })
    in ["GET", %r{\A/v2/inAppPurchases/([\w-]+)/pricePoints\z}]
      list(points("inAppPurchase", params["filter[territory]"]))
    in ["POST", "/v1/inAppPurchasePriceSchedules"]
      iap = body["data"]["relationships"]["inAppPurchase"]["data"]["id"]
      territory = body["data"]["relationships"]["baseTerritory"]["data"]["id"]
      point = body["included"][0]["relationships"]["inAppPurchasePricePoint"]["data"]["id"]
      all("inAppPurchasePrices", schedule: iap).each { |r| @store["inAppPurchasePrices"].delete(r["id"]) }
      @store["inAppPurchasePriceSchedules"][iap] = { "type" => "inAppPurchasePriceSchedules", "id" => iap, "attributes" => {}, "rel" => {} }
      add("inAppPurchasePrices", { "startDate" => nil }, { "schedule" => iap, "territory" => territory, "inAppPurchasePricePoint" => point })
      { "data" => json(@store["inAppPurchasePriceSchedules"][iap]) }
    in ["GET", %r{\A/v2/inAppPurchases/([\w-]+)/inAppPurchaseAvailability\z}]
      one(all("inAppPurchaseAvailabilities", inAppPurchase: $1).first)
    in ["POST", "/v1/inAppPurchaseAvailabilities"]
      { "data" => json(create(body)) }
    in ["GET", %r{\A/v2/inAppPurchases/([\w-]+)/appStoreReviewScreenshot\z}]
      { "data" => json(all("inAppPurchaseAppStoreReviewScreenshots", inAppPurchaseV2: $1).first) }
    in ["POST", "/v1/inAppPurchaseAppStoreReviewScreenshots" | "/v1/subscriptionAppStoreReviewScreenshots"]
      record = create(body)
      size = record["attributes"]["fileSize"]
      record["attributes"]["uploadOperations"] = [
        { "method" => "PUT", "url" => "https://upload.example/#{record['id']}/0", "offset" => 0, "length" => size / 2, "requestHeaders" => [] },
        { "method" => "PUT", "url" => "https://upload.example/#{record['id']}/1", "offset" => size / 2, "length" => size - size / 2, "requestHeaders" => [] }
      ]
      { "data" => json(record) }
    in ["PATCH", %r{\A/v1/(inAppPurchaseAppStoreReviewScreenshots|subscriptionAppStoreReviewScreenshots)/([\w-]+)\z}]
      update($1, $2, body)

    # Subscriptions
    in ["GET", %r{\A/v1/apps/(\w+)/subscriptionGroups\z}]
      list(all("subscriptionGroups", app: $1))
    in ["POST", "/v1/subscriptionGroups"]
      record = create(body)
      new_version("subscriptionGroup", "subscriptionGroup", record["id"]) if @versions
      { "data" => json(record) }
    in ["PATCH", %r{\A/v1/subscriptionGroups/([\w-]+)\z}]
      update("subscriptionGroups", $1, body)
    in ["GET", %r{\A/v1/subscriptionGroups/([\w-]+)/versions\z}]
      list(all("subscriptionGroupVersions", subscriptionGroup: $1))
    in ["GET", %r{\A/v1/subscriptionGroupVersions/([\w-]+)/localizations\z}]
      list(all("subscriptionGroupLocalizations", version: $1))
    in ["GET", %r{\A/v1/subscriptionGroups/([\w-]+)/subscriptionGroupLocalizations\z}]
      list(all("subscriptionGroupLocalizations", subscriptionGroup: $1))
    in ["POST", "/v1/subscriptionGroupLocalizations" | "/v2/subscriptionGroupLocalizations"]
      { "data" => json(create(body)) }
    in ["PATCH", %r{\A/v[12]/subscriptionGroupLocalizations/([\w-]+)\z}]
      update("subscriptionGroupLocalizations", $1, body)
    in ["GET", %r{\A/v1/subscriptionGroups/([\w-]+)/subscriptions\z}]
      list(all("subscriptions", group: $1))
    in ["POST", "/v1/subscriptions"]
      record = create(body)
      record["attributes"]["state"] = "MISSING_METADATA"
      new_version("subscription", "subscription", record["id"]) if @versions
      { "data" => json(record) }
    in ["PATCH", %r{\A/v1/subscriptions/([\w-]+)\z}]
      update("subscriptions", $1, body)
    in ["GET", %r{\A/v1/subscriptions/([\w-]+)/versions\z}]
      list(all("subscriptionVersions", subscription: $1))
    in ["POST", "/v1/subscriptionVersions"]
      parent = body["data"]["relationships"]["subscription"]["data"]["id"]
      { "data" => json(@store["subscriptionVersions"][new_version("subscription", "subscription", parent)]) }
    in ["GET", %r{\A/v1/subscriptionVersions/([\w-]+)/localizations\z}]
      list(all("subscriptionLocalizations", version: $1))
    in ["GET", %r{\A/v1/subscriptions/([\w-]+)/subscriptionLocalizations\z}]
      list(all("subscriptionLocalizations", subscription: $1))
    in ["POST", "/v1/subscriptionLocalizations" | "/v2/subscriptionLocalizations"]
      { "data" => json(create(body)) }
    in ["PATCH", %r{\A/v[12]/subscriptionLocalizations/([\w-]+)\z}]
      update("subscriptionLocalizations", $1, body)
    in ["GET", %r{\A/v1/subscriptions/([\w-]+)/planAvailabilities\z}]
      list(all("subscriptionPlanAvailabilities", subscription: $1))
    in ["POST", "/v1/subscriptionPlanAvailabilities"]
      { "data" => json(create(body)) }
    in ["GET", %r{\A/v1/subscriptions/([\w-]+)/prices\z}]
      prices = all("subscriptionPrices", subscription: $1).select { |r| r["rel"]["territory"] == params["filter[territory]"] }
      list(prices, prices.map { |r| @store["subscriptionPricePoints"][r["rel"]["subscriptionPricePoint"]] })
    in ["GET", %r{\A/v1/subscriptions/([\w-]+)/pricePoints\z}]
      list(points("subscription", params["filter[territory]"]))
    in ["GET", %r{\A/v1/subscriptionPricePoints/subscription-(\w+)-([\d.]+)/equalizations\z}]
      list((TERRITORIES - [$1]).map { |t| points("subscription", t).find { |pt| pt["attributes"]["customerPrice"] == $2 } })
    in ["POST", "/v1/subscriptionPrices"]
      { "data" => json(create(body)) }
    in ["GET", %r{\A/v1/subscriptions/([\w-]+)/appStoreReviewScreenshot\z}]
      { "data" => json(all("subscriptionAppStoreReviewScreenshots", subscription: $1).first) }
    else
      raise "FakeAppStoreConnect doesn't know #{method} #{p}"
    end
  end
end
