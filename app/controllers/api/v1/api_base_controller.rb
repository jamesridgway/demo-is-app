class Api::V1::ApiBaseController < ApplicationController

  def json_response(object, status = :ok)
    render json: object, status: status
  end

end
