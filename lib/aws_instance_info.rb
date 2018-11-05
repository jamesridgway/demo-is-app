require 'aws-sdk'
require 'json'
require 'net/http'
class AwsInstanceInfo

  def initialize
    @ec2 = Aws::EC2::Client.new
  end

  def get_instance_type
    return 't3.large' if instance_identity.empty?
    return instance_identity['instanceType']
  end

  def get_instance_id
    return 'unknown' if instance_identity.empty?
    return instance_identity['instanceId']
  end

  def get_region
    return 'unknown' if instance_identity.empty?
    return instance_identity['region']
  end

  def get_on_demand_price(frequency)
    @on_demand_price ||= Rails.cache.fetch('calculate_on_demand_price', :expires_in => 1.day) do
      calculate_on_demand_price
    end
    if frequency == :monthly
      return @on_demand_price * 24 * 31
    end
    if frequency == :daily
      return @on_demand_price * 24
    end
    return @on_demand_price
  end

  def get_spot_price(frequency)
    @spot_price ||= Rails.cache.fetch('calculate_spot_price', :expires_in => 1.day) do
      calculate_spot_price
    end
    if frequency == :monthly
      return @spot_price * 24 * 31
    end
    if frequency == :daily
      return @spot_price * 24
    end
    return @spot_price
  end

  private

  def instance_identity
    Rails.cache.fetch('instance_identity', :expires_in => 1.day) do
      puts "### instance_identity ###"
      return JSON.parse(Net::HTTP.get(URI('http://169.254.169.254/latest/dynamic/instance-identity/document')))
    rescue
      return {}
    end
  end

  def calculate_on_demand_price
    pricing_client = Aws::Pricing::Client.new(region: 'us-east-1')
    resp = pricing_client.get_products({
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
    price_dimensions = prices[sku]['priceDimensions']
    return price_dimensions[price_dimensions.keys.first]['pricePerUnit']['USD'].to_f
  end

  def calculate_spot_price
    return 0 if instance_identity.empty?
    launch_time = @ec2.describe_instances({instance_ids: [get_instance_id]}).reservations[0].instances[0].launch_time
    @ec2.describe_spot_price_history({
                                         end_time: launch_time,
                                         instance_types: [
                                             get_instance_type,
                                         ],
                                         product_descriptions: [
                                             "Linux/UNIX (Amazon VPC)",
                                         ],
                                         start_time: launch_time - 1.hour.ago,
                                     }).spot_price_history[0]['spot_price'].to_f
  end

end