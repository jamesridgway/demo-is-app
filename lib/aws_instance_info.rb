require 'net/http'
require 'json'
require 'aws-sdk'
class AwsInstanceInfo

  def initialize
    @instance_identity = {}
    begin
      @instance_identity = JSON.parse(Net::HTTP.get(URI('http://169.254.169.254/latest/dynamic/instance-identity/document')))
    rescue
      # ignored
    end
    @ec2 = Aws::EC2::Client.new(region: 'eu-west-1')
    @pricing_client = Aws::Pricing::Client.new(region: 'us-east-1')
  end

  def get_instance_type
    return 't3.large' if @instance_identity.empty?
    return @instance_identity['instanceType']
  end

  def get_instance_id
    return 'unknown' if @instance_identity.empty?
    return @instance_identity['instanceId']
  end

  def get_region
    return 'unknown' if @instance_identity.empty?
    return @instance_identity['region']
  end

  def get_on_demand_price(frequency)
    @on_demand_price ||= calculate_on_demand_price
    if frequency == :monthly
      return @on_demand_price * 24 * 31
    end
    if frequency == :daily
      return @on_demand_price * 24
    end
    return @on_demand_price
  end

  def get_spot_price(frequency)
    @spot_price ||= calculate_spot_price
    if frequency == :monthly
      return @spot_price * 24 * 31
    end
    if frequency == :daily
      return @spot_price * 24
    end
    return @spot_price
  end

  private

  def calculate_on_demand_price
    return 0
    resp = @pricing_client.get_products({
                                            service_code: 'AmazonEC2',
                                            filters: [
                                                {
                                                    field: 'tenancy',
                                                    type: 'TERM_MATCH',
                                                    value: 'shared',
                                                },
                                                {
                                                    field: 'operatingSystem',
                                                    type: 'TERM_MATCH',
                                                    value: 'Linux',
                                                },
                                                {
                                                    field: 'preInstalledSw',
                                                    type: 'TERM_MATCH',
                                                    value: 'NA',
                                                },
                                                {
                                                    field: 'instanceType',
                                                    type: 'TERM_MATCH',
                                                    value: get_instance_type,
                                                },
                                                {
                                                    field: 'capacitystatus',
                                                    type: 'TERM_MATCH',
                                                    value: 'used',
                                                },
                                                {
                                                    field: 'location',
                                                    type: 'TERM_MATCH',
                                                    value: 'EU (Ireland)',
                                                }
                                            ],
                                            format_version: 'aws_v1',
                                            max_results: 1
                                        })
    prices = JSON.parse(resp.price_list[0])['terms']['OnDemand']
    sku = prices.keys.first
    priceDimensions = prices[sku]['priceDimensions']
    return priceDimensions[priceDimensions.keys.first]['pricePerUnit']['USD'].to_f
  end

  def calculate_spot_price
    return 0 if @instance_identity.empty?
    @ec2.describe_spot_price_history({
                                           end_time: Time.now,
                                           instance_types: [
                                               get_instance_type,
                                           ],
                                           product_descriptions: [
                                               "Linux/UNIX (Amazon VPC)",
                                           ],
                                           start_time: Time.now,
                                       }).spot_price_history[0]['spot_price'].to_f
  end

end