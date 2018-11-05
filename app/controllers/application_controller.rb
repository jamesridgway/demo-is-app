class ApplicationController < ActionController::Base
  before_action :git_version_info
  private

  def git_version_info
    @git_version_info = Rails.cache.fetch('git_version_info') do
      GitVersionInfo.new
    end
  end

end
