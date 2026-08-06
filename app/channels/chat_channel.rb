class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "chat_#{params[:room]}"
  end

  def unsubscribed
    stop_all_streams
  end

  def receive(data)
    ActionCable.server.broadcast("chat_#{params[:room]}", {
      message: data["message"],
      user: current_user&.email || "anonymous",
      timestamp: Time.current
    })
  end
end
