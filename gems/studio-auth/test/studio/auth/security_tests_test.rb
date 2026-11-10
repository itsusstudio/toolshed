require "test_helper"

class Studio::Auth::SecurityTestsTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelpers
  include Studio::Auth::SecurityTests
end
