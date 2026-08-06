class PostsController < ApplicationController
  before_action :set_post, only: %i[ show edit update destroy ]
  before_action :authenticate_user!, only: %i[ new create edit update destroy ]

  def index
    @posts = Post.recent.page(params[:page] || 1).per(10)
    @posts = @posts.by_title(params[:q]) if params[:q].present?
  end

  # Same read path as #index, paginated with plain limit/offset instead of
  # Kaminari.
  def index_plain
    page = [ params[:page].to_i, 1 ].max
    @posts = Post.recent.limit(10).offset((page - 1) * 10)
  end

  def show
    @comments = @post.comments.recent
  end

  def new
    @post = Post.new
  end

  def edit
  end

  def create
    @post = Post.new(post_params)
    @post.user = current_user

    if @post.save
      redirect_to @post, notice: t("posts.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @post.update(post_params)
      redirect_to @post, notice: t("posts.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy
    redirect_to posts_url, notice: t("posts.destroyed")
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def post_params
    params.require(:post).permit(:title, :body, :category_id)
  end
end
