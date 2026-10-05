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
  get "/job_enqueue_probe", to: "stats#job_enqueue_probe"
  get "/downloads/posts_csv", to: "downloads#posts_csv", as: :posts_csv_download
  get "/downloads/report", to: "downloads#report", as: :report_download
  get "/posts_plain", to: "posts#index_plain", as: :posts_plain
  scope :features do
    get "/conditional_get", to: "features#conditional_get"
    get "/cookie_jar", to: "features#cookie_jar"
    get "/head", to: "features#head_probe"
    get "/basic_auth", to: "features#basic_auth"
    get "/form_probe", to: "features#form_probe"
    post "/form_echo", to: "features#form_echo"
    get "/current", to: "features#current_attrs"
    get "/rich_text", to: "features#rich_text"
  end
  get "up" => "rails/health#show", as: :rails_health_check
  root "posts#index"
end
