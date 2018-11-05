class WelcomeController < ApplicationController

  def index
    @aws_instance_info = AwsInstanceInfo.new
  end
end
