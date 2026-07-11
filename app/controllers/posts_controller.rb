class PostsController < ApplicationController
  before_action :set_post, only: %i[ show edit update destroy ]
  before_action :authenticate_user!, only: %i[ new create edit update destroy ]

  def index
    @posts = Post.order(created_at: :desc).page(params[:page] || 1).per(10)
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
