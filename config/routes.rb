Rails.application.routes.draw do
  resource :session
  resource :account, only: [ :show ] do
    patch :rotate_key
  end
  resources :passwords, param: :token
  resources :projects do
    member do
      get :settings
      patch :rotate_key
    end
    resources :error_groups, only: [ :show ] do
      member do
        patch :resolve
        patch :ignore
        patch :unresolve
        patch :workflow_state, action: :update_workflow_state
        post :send_notification
      end
      resources :notes, controller: :error_group_notes, only: [ :create ]
    end
    resources :notification_rules, only: [ :create, :edit, :update, :destroy ] do
      member do
        patch :toggle
      end
      collection do
        post :test_send
      end
    end
  end

  namespace :api do
    namespace :v1 do
      resources :exceptions, only: [ :create ]
      resource :project, only: [ :show ]
      post "projects", to: "projects#create"
      patch "projects/:id", to: "projects#update", as: :project_admin
      patch "projects/:id/disable", to: "projects#disable", as: :disable_project_admin
      patch "projects/:id/enable", to: "projects#enable", as: :enable_project_admin
      resources :notification_rules, only: [ :index, :create ]
      resources :error_groups, only: [ :index, :show ] do
        member do
          patch :resolve
          patch :ignore
          patch :unresolve
          patch :workflow_state, action: :update_workflow_state
        end
        resources :notes, controller: :error_group_notes, only: [ :create ]
      end
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "cli" => "cli#show", as: :cli
  get "skills" => "skills#show", as: :skills

  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#show"
end
