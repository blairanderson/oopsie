module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate!
      before_action :check_rate_limit!

      private

      def authenticate!
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")

        unless token.present?
          render json: { error: "Invalid API key" }, status: :unauthorized
          return
        end

        if (api_token = ApiToken.authenticate(token))
          @api_token = api_token
          @user = api_token.user
          @project = api_token.project
          api_token.record_use!(client: request_client_label)
          return
        end

        @project = Project.find_by(api_key: token)
        return if @project

        @user = User.find_by(api_key: token)
        return if @user

        render json: { error: "Invalid API key" }, status: :unauthorized
      end

      def current_project
        @project
      end

      def current_user
        @user
      end

      def require_user_key!
        return if @user

        render json: { error: "User API key required" }, status: :forbidden
      end

      def require_project!
        return if @project

        if @user
          project_id = params[:project_id] || request.headers["X-Project-Id"]
          @project = Project.find_by(id: project_id) if project_id
        end

        unless @project
          render json: { error: "Project context required. Pass project_id param or X-Project-Id header." }, status: :bad_request
        end
      end

      def require_project_accepts_ingest!
        return if performed?
        return if @project&.accepts_ingest?

        render json: {
          error: "Project is disabled and cannot accept new exceptions",
          project: {
            id: @project.id,
            name: @project.name,
            status: @project.status,
            disabled_at: @project.disabled_at&.iso8601
          }
        }, status: :forbidden
      end

      def check_rate_limit!
        rate_key = if @api_token
          "token:#{@api_token.id}"
        elsif @project
          "project:#{@project.id}"
        else
          "user:#{@user.id}"
        end
        cache_key = "rate_limit:#{rate_key}:#{Time.current.to_i / 60}"
        count = Rails.cache.increment(cache_key, 1, expires_in: 2.minutes) || 1

        if count > 100
          render json: { error: "Rate limit exceeded" }, status: :too_many_requests
        end
      end

      def request_client_label
        request.headers["X-Oopsie-Client"].presence || request.user_agent.to_s
      end
    end
  end
end
