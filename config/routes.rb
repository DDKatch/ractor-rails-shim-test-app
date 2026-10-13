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
  get "/mail_hooks_probe", to: "stats#mail_hooks_probe"
  get "/job_enqueue_probe", to: "stats#job_enqueue_probe"
  get "/cable_probe", to: "stats#cable_probe"
  get "/solid_cache_probe", to: "stats#solid_cache_probe"
get "/assoc_probe", to: "stats#assoc_probe"
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
    get "/validations_probe", to: "features#validations_probe"
    get "/enum_probe", to: "features#enum_probe"
    get "/dirty_probe", to: "features#dirty_probe"
    get "/batch_probe", to: "features#batch_probe"
    get "/aggregate_probe", to: "features#aggregate_probe"
    get "/signed_id_probe", to: "features#signed_id_probe"
    get "/bulk_probe", to: "features#bulk_probe"
    get "/job_resilience_probe", to: "features#job_resilience_probe"
    get "/optimistic_lock_probe", to: "features#optimistic_lock_probe"
    get "/pessimistic_lock_probe", to: "features#pessimistic_lock_probe"
    get "/normalizes_probe", to: "features#normalizes_probe"
    get "/default_scope_probe", to: "features#default_scope_probe"
    get "/strict_loading_probe", to: "features#strict_loading_probe"
    get "/load_async_probe", to: "features#load_async_probe"
    get "/audit_archive_probe", to: "features#audit_archive_probe"
    get "/builder_form_probe", to: "features#builder_form_probe"
    get "/text_helpers_probe", to: "features#text_helpers_probe"
    get "/composite_pk_probe", to: "features#composite_pk_probe"
    get "/current", to: "features#current_attrs"
    get "/rich_text", to: "features#rich_text"
  end
  get "up" => "rails/health#show", as: :rails_health_check
  root "posts#index"
end
