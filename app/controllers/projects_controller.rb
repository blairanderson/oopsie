class ProjectsController < ApplicationController
  before_action :set_project, only: [ :show, :edit, :update, :destroy, :settings, :rotate_key ]

  def index
    unresolved_count_sql = ActiveRecord::Base.sanitize_sql_array(
      [ "COUNT(CASE WHEN error_groups.status = ? THEN 1 END) AS unresolved_count", ErrorGroup.statuses[:unresolved] ]
    )
    @projects = Project.left_joins(:error_groups)
      .select("projects.*, #{unresolved_count_sql}")
      .group("projects.id")
      .order("projects.name ASC")
  end

  def show
    @error_groups = @project.error_groups.by_last_seen
  end

  def settings
    @notification_rules = @project.notification_rules.order(:created_at)
    @notification_rule = @project.notification_rules.build
    @api_tokens = @project.api_tokens.order(Arel.sql("CASE WHEN revoked_at IS NULL THEN 0 ELSE 1 END"), created_at: :desc)
  end

  def new
    @project = Project.new
  end

  def create
    @project = Project.new(project_params)

    if @project.save
      redirect_to projects_path, notice: "Project created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @project.update(project_params)
      redirect_to @project, notice: "Project updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def rotate_key
    @project.regenerate_api_key!
    redirect_to settings_project_path(@project), notice: "Project key regenerated. Update any integrations using the old key."
  end

  def destroy
    @project.destroy
    redirect_to projects_path, notice: "Project deleted."
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name)
  end
end
