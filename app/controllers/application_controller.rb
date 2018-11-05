class ApplicationController < ActionController::Base
  before_action :load_data

  private

  def load_data
    @git_version_info = Rails.cache.fetch('git_version_info') do
      GitVersionInfo.new
    end
  end

end
