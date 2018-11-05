require 'aws-sdk'
require 'base64'
require 'logger'
require 'json'
require 'net/http'

$stdout.sync = true
logger = Logger.new($stdout)

aws_region = JSON.parse(Net::HTTP.get(URI("http://169.254.169.254/latest/dynamic/instance-identity/document")))["region"]

ec2 = Aws::EC2::Client.new(region: aws_region)
elbv2 = Aws::ElasticLoadBalancingV2::Client.new(region: aws_region)
iam = Aws::IAM::Client.new(region: aws_region)

packer_manifest = JSON.parse(File.read('manifest.json'))
ami_id = packer_manifest['builds'][0]['artifact_id'].split(':')[1]
logger.info("AMI ID: #{ami_id}")

WEBSITE_TARGET_GROUP_ARN = elbv2.describe_target_groups({names: ['website']}).target_groups[0].target_group_arn

logger.info("Using ELB target group: #{WEBSITE_TARGET_GROUP_ARN}")

existing_website_spot_fleet_request_ids = []

ec2.describe_spot_fleet_requests.each do |resps|
  resps.spot_fleet_request_configs.each do |fleet_request|
    if fleet_request.spot_fleet_request_state == 'active' || fleet_request.spot_fleet_request_state == 'modifying'
      target_groups_config = fleet_request.spot_fleet_request_config.load_balancers_config.target_groups_config
      if target_groups_config.target_groups.all? {|tg| tg.arn == WEBSITE_TARGET_GROUP_ARN}
        existing_website_spot_fleet_request_ids << fleet_request.spot_fleet_request_id
      end
    end
  end
end

iam_fleet_role = iam.get_role({role_name: 'aws-ec2-spot-fleet-tagging-role'}).role.arn

default_sg_id = ec2.describe_security_groups({
                                                 filters: [
                                                     {
                                                         name: "description",
                                                         values: [
                                                             "default VPC security group",
                                                         ],
                                                     },
                                                 ],
                                             }).security_groups[0].group_id

rails_app_sg_id = ec2.describe_security_groups({
                                                 filters: [
                                                     {
                                                         name: "tag:Name",
                                                         values: [
                                                             "Rails App",
                                                         ],
                                                     },
                                                 ],
                                             }).security_groups[0].group_id


logger.info("IAM Fleet Role ARN: #{iam_fleet_role}")
logger.info("Default Security Group: #{default_sg_id}")
logger.info("Rails App Security Group: #{rails_app_sg_id}")

logger.info("Existing website fleet requests: #{existing_website_spot_fleet_request_ids}")

response = ec2.request_spot_fleet({
                                      spot_fleet_request_config: {
                                          allocation_strategy: 'lowestPrice',
                                          on_demand_allocation_strategy: "lowestPrice",
                                          excess_capacity_termination_policy: "noTermination",
                                          fulfilled_capacity: 1.0,
                                          on_demand_fulfilled_capacity: 1.0,
                                          iam_fleet_role: iam_fleet_role,
                                          launch_specifications: [
                                              {
                                                  security_groups: [
                                                      {
                                                          group_id: default_sg_id
                                                      },
                                                      {
                                                          group_id: rails_app_sg_id
                                                      }
                                                  ],
                                                  iam_instance_profile: {
                                                      name: "website",
                                                  },
                                                  image_id: ami_id,
                                                  instance_type: "t3.micro",
                                                  key_name: "demo",
                                                  tag_specifications: [
                                                      {
                                                          resource_type: "instance",
                                                          tags: [
                                                              {
                                                                  key: "Name",
                                                                  value: "demo-web-app",
                                                              },
                                                              {
                                                                  key: "Project",
                                                                  value: "demo-web-app",
                                                              },
                                                          ],
                                                      }
                                                  ],
                                              },
                                          ],
                                          target_capacity: 2,
                                          type: 'maintain',
                                          valid_from: Time.now,
                                          replace_unhealthy_instances: false,
                                          instance_interruption_behavior: 'terminate',
                                          load_balancers_config: {
                                              target_groups_config: {
                                                  target_groups: [
                                                      {
                                                          arn: WEBSITE_TARGET_GROUP_ARN
                                                      },
                                                  ],
                                              },
                                          },
                                      },
                                  })

logger.info("Launching spot instance request: '#{response.spot_fleet_request_id}'")


spot_provisioned = false
begin
  ec2.describe_spot_fleet_requests({spot_fleet_request_ids: [response.spot_fleet_request_id]}).each do |resps|
    resps.spot_fleet_request_configs.each do |fleet_request|
      if fleet_request.activity_status == 'fulfilled'
        spot_provisioned = true
      end
      if fleet_request.activity_status == 'error'
        logger.error("Provisioning spot instance request '#{response.spot_fleet_request_id}' has failed!")
        exit 1
      end
      logger.info("Spot instance request '#{response.spot_fleet_request_id}' has activity status: '#{fleet_request.activity_status}'")
      sleep 10
    end
  end
end until spot_provisioned
logger.info("Launched spot instance request: '#{response.spot_fleet_request_id}' !")
sleep 10


target_group_resp = elbv2.describe_target_health({target_group_arn: WEBSITE_TARGET_GROUP_ARN})
until target_group_resp.target_health_descriptions.all? {|thd| thd.target_health.state == 'healthy'}
  total_instances = target_group_resp.target_health_descriptions.size
  healthy_instances = target_group_resp.target_health_descriptions.count {|thd| thd.target_health.state == 'healthy'}
  unhealthy_instances = target_group_resp.target_health_descriptions.count {|thd| thd.target_health.state == 'unhealthy'}

  logger.info("#{total_instances} total instances in target group. #{healthy_instances} healthy instances...")

  if unhealthy_instances > 0
    logger.error("#{unhealthy_instances} unhealthy instances! aborting...")
    ec2.cancel_spot_fleet_requests(spot_fleet_request_ids: [response.spot_fleet_request_id], terminate_instances: true)
    logger.error("Cancelled new fleet request (id: #{response.spot_fleet_request_id})")
  end

  if total_instances != healthy_instances
    sleep 10
    target_group_resp = elbv2.describe_target_health({target_group_arn: WEBSITE_TARGET_GROUP_ARN})

    total_instances = target_group_resp.target_health_descriptions.size
    healthy_instances = target_group_resp.target_health_descriptions.count {|thd| thd.target_health.state == 'healthy'}
    unhealthy_instances = target_group_resp.target_health_descriptions.count {|thd| thd.target_health.state == 'unhealthy'}

    logger.info("#{total_instances} total instances in target group. #{healthy_instances} healthy instances...")
  end
end

sleep 10

unless existing_website_spot_fleet_request_ids.empty?
  logger.info("Cancelling old spot instances: #{existing_website_spot_fleet_request_ids}")
  ec2.cancel_spot_fleet_requests(spot_fleet_request_ids: existing_website_spot_fleet_request_ids, terminate_instances: true)
end

logger.info("Deployed!")