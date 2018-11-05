class Api::V1::VersionController < Api::V1::ApiBaseController

  def index
    version_info = {
        revision: @git_version_info.commit,
        short_revision: @git_version_info.commit_short
    }
    json_response(version_info)
  end
end
