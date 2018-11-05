Rails.application.routes.draw do

  namespace :api do
    namespace :v1 do
      resource :api_base, path: '/', only: []
      resources :version, only: :index
    end
  end

  root 'welcome#index'
end
