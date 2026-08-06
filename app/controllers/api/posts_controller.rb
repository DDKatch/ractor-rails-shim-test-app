module Api
  class PostsController < ApplicationController
    skip_before_action :verify_authenticity_token
    respond_to :json

    def index
      @posts = Post.recent.includes(:user, :category, :comments)
      render json: @posts.map { |p| post_json(p) }
    end

    def show
      @post = Post.includes(:user, :category, :comments).find(params[:id])
      render json: post_json(@post, full: true)
    end

    def create
      @post = Post.new(post_params)
      @post.user = current_user if respond_to?(:current_user) && current_user

      if @post.save
        render json: post_json(@post), status: :created
      else
        render json: { errors: @post.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      @post = Post.find(params[:id])
      if @post.update(post_params)
        render json: post_json(@post)
      else
        render json: { errors: @post.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @post = Post.find(params[:id])
      @post.destroy
      head :no_content
    end

    private

    def post_params
      params.require(:post).permit(:title, :body, :category_id)
    end

    def post_json(post, full: false)
      data = {
        id: post.id,
        title: post.title,
        body: post.body,
        created_at: post.created_at,
        updated_at: post.updated_at,
        comments_count: post.comments.size,
        user: post.user ? { id: post.user.id, email: post.user.email } : nil,
        category: post.category ? { id: post.category.id, name: post.category.name } : nil
      }
      if full
        data[:comments] = post.comments.includes(:user).map do |c|
          { id: c.id, body: c.body, user_email: c.user&.email, created_at: c.created_at }
        end
      end
      data
    end
  end
end
