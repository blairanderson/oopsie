module Api
  module V1
    class ExceptionsController < BaseController
      before_action :require_project!
      before_action :require_project_accepts_ingest!
      before_action :validate_payload!

      rescue_from ActiveRecord::RecordInvalid do |e|
        render json: { error: "Unprocessable Entity", details: e.record.errors.full_messages }, status: :unprocessable_entity
      end

      def create
        error = params[:error]
        first_line = error[:first_line]&.permit(:file, :line, :method)&.to_h

        fingerprint = ErrorGroup.generate_fingerprint(
          error_class: error[:class_name],
          first_line: first_line,
          message: error[:message]
        )

        is_new_group = false
        was_resolved = false

        error_group = @project.error_groups.find_by(fingerprint: fingerprint)

        if error_group
          was_resolved = error_group.resolved?
          error_group.update!(
            last_seen_at: Time.current,
            message: error[:message].presence || error_group.message
          )
          if was_resolved
            error_group.transition_status!(
              :unresolved,
              actor: { kind: "system", label: "regression detector" },
              source: "api",
              note: "Reopened automatically because a resolved error occurred again."
            )
          end
        else
          is_new_group = true
          error_group = @project.error_groups.create!(
            fingerprint: fingerprint,
            error_class: error[:class_name],
            message: error[:message],
            status: :unresolved,
            first_seen_at: Time.current,
            last_seen_at: Time.current
          )
        end

        occurrence = error_group.occurrences.create!(
          message: error[:message],
          backtrace: error[:backtrace],
          first_line: first_line,
          causes: error[:causes],
          handled: error[:handled] || false,
          context: context_params,
          environment: params.dig(:app, :environment),
          server_info: server_params,
          occurred_at: params[:timestamp] || Time.current,
          notifier_version: params[:version]
        )

        # Notify on new error groups or regressions
        if is_new_group || was_resolved
          NotifyJob.perform_later(
            error_group_id: error_group.id,
            occurrence_id: occurrence.id,
            is_regression: was_resolved
          )
        end

        render json: {
          id: occurrence.id,
          group_id: error_group.id,
          is_new_group: is_new_group
        }, status: :created
      end

      private

      def context_params
        parsed_body["context"] if parsed_body["context"].is_a?(Hash)
      end

      def server_params
        parsed_body["server"] if parsed_body["server"].is_a?(Hash)
      end

      def parsed_body
        @parsed_body ||= JSON.parse(request.raw_post)
      rescue JSON::ParserError
        {}
      end

      def validate_payload!
        errors = []
        errors << "Missing error object" unless params[:error].is_a?(ActionController::Parameters)
        if params[:error].is_a?(ActionController::Parameters)
          errors << "Missing error.class_name" unless params[:error][:class_name].present?
        end

        if errors.any?
          render json: { error: "Unprocessable Entity", details: errors }, status: :unprocessable_entity
        end
      end
    end
  end
end
