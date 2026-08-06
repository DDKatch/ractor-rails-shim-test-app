Rails.application.routes.draw do
  devise_for :users

  resources :posts do
    resources :comments, only: %i[create edit update destroy]
  end

  resources :categories

  namespace :api do
    resources :posts, only: %i[index show create update destroy]
  end

  get "/stats", to: "stats#show"
  get "/posts_plain", to: "posts#index_plain", as: :posts_plain
  get "up" => "rails/health#show", as: :rails_health_check
  root "posts#index"
end
