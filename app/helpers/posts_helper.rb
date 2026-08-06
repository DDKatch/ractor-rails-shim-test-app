module PostsHelper
  def post_status_badge(post)
    age = (Time.current - post.created_at) / 1.day
    if age < 1
      content_tag(:span, "New", class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800")
    elsif age < 7
      content_tag(:span, "Recent", class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800")
    else
      content_tag(:span, "Archive", class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-800")
    end
  end
end
