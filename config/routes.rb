Rails.application.routes.draw do
  devise_for :users
  get "/stats", to: "stats#show"
  resources :posts, only: %i[index show new edit create update destroy]
  get "/posts_plain", to: "posts#index_plain", as: :posts_plain
  get "up" => "rails/health#show", as: :rails_health_check
  root "posts#index"
end
