class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_csrf_error

  private

  def record_not_found
    respond_to do |format|
      format.html { render plain: "Not found", status: :not_found }
      format.json { render json: { error: "Record not found" }, status: :not_found }
    end
  end

  def handle_csrf_error
    respond_to do |format|
      format.html { render plain: "CSRF token invalid", status: :unprocessable_entity }
      format.json { render json: { error: "CSRF token invalid" }, status: :unprocessable_entity }
    end
  end
end
