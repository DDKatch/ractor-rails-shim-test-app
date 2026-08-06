module ApplicationHelper
  def page_title(title)
    title_str = "#{title} | Ractor Test App"
    if respond_to?(:content_for)
      result = content_for(:title) { title_str }
      result || title_str.html_safe
    else
      title_str.html_safe
    end
  end

  def time_ago(date)
    return "just now" unless date
    "#{time_ago_in_words(date)} ago"
  end

  def badge_count(count)
    return "" if count.zero?
    content_tag(:span, count, class: "inline-flex items-center justify-center px-2 py-1 text-xs font-bold leading-none text-white bg-blue-600 rounded-full")
  end

  def flash_messages
    flash.each do |type, message|
      next if message.blank?
      css_class = case type.to_sym
      when :notice, :success then "bg-green-100 text-green-800 border-green-300"
      when :alert, :error then "bg-red-100 text-red-800 border-red-300"
      when :warning then "bg-yellow-100 text-yellow-800 border-yellow-300"
      else "bg-blue-100 text-blue-800 border-blue-300"
      end
      concat content_tag(:div, message, class: "p-4 mb-4 rounded border #{css_class}", role: "alert")
    end
  end

  def gravatar_url(email, size: 40)
    hash = Digest::MD5.hexdigest(email.to_s.downcase.strip)
    "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=mp"
  end

  def truncate_with_length(text, length: 100)
    truncate(text.to_s, length: length, separator: " ")
  end
end
