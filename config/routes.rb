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
  get "/json_probe", to: "stats#json_probe"
  get "/scope_probe", to: "stats#scope_probe"
  get "/mail_probe", to: "stats#mail_probe"
  get "/attach_probe", to: "stats#attach_probe"
  get "/attach_read_probe", to: "stats#attach_read_probe"
  get "/mail_deliver_probe", to: "stats#mail_deliver_probe"
  get "/posts_plain", to: "posts#index_plain", as: :posts_plain
  get "up" => "rails/health#show", as: :rails_health_check
  root "posts#index"
end
