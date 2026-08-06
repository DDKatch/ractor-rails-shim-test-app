module CategoriesHelper
  def category_options_for_select
    Category.alphabetical.map { |c| [c.name, c.id] }
  end
end
