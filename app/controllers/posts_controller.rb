class PostsController < ApplicationController
  before_action :set_post, only: %i[ show edit update destroy ]
  before_action :authenticate_user!, only: %i[ new create edit update destroy ]

  def index
    @posts = Post.order(created_at: :desc).page(params[:page] || 1).per(10)
  end

  # Same read path as #index, paginated with plain limit/offset instead of
  # Kaminari. Kaminari's page scope runs Module.new + include + extending!
  # on every call; those request-time method-table mutations are cheap on a
  # single-Ractor server but cost a stop-all-Ractors barrier plus a global
  # method-cache invalidation when worker Ractors run in parallel. Benching
  # both endpoints side by side separates "Rails under Ractors" from that
  # per-request mutation cost.
  def index_plain
    page = [ params[:page].to_i, 1 ].max
    @posts = Post.order(created_at: :desc).limit(10).offset((page - 1) * 10)
  end
  def show
  end
  def new
    @post = Post.new
  end
  def edit
  end
  def create
    @post = Post.new(post_params)
    if @post.save
      redirect_to @post, notice: "Post created."
    else
      render :new, status: :unprocessable_entity
    end
  end
  def update
    if @post.update(post_params)
      redirect_to @post, notice: "Post updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end
  def destroy
    @post.destroy
    redirect_to posts_url, notice: "Post deleted."
  end
  private
  def set_post
    @post = Post.find(params[:id])
  end
  def post_params
    params.require(:post).permit(:title, :body)
  end
end
