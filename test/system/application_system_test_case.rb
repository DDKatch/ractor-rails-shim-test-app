require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # driven_by :rack_test needs no browser (the audit doesn't exercise JS);
  # selenium-webdriver is installed for future JS-driven system tests.
  driven_by :rack_test
end
