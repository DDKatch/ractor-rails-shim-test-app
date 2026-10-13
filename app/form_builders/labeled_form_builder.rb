# RAILS_FEATURES.md row 97: custom form builders. A thin FormBuilder
# subclass whose `labeled_text_field` wraps label + field in one styled
# <div>, so views stop repeating the same label/field markup. Passed to
# form_with via `builder: LabeledFormBuilder`.
class LabeledFormBuilder < ActionView::Helpers::FormBuilder
  def labeled_text_field(attribute, **options)
    @template.content_tag(:div, class: "labeled-field") do
      label(attribute) + text_field(attribute, options)
    end
  end
end
