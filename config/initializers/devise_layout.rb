# Render Devise auth pages (sessions / registrations / passwords / etc.)
# inside the dedicated `devise` layout (full-screen gradient, no app header).
%w[Sessions Registrations Passwords Confirmations Unlocks].each do |name|
  controller = "Devise::#{name}Controller".safe_constantize
  controller.layout "devise" if controller
end
