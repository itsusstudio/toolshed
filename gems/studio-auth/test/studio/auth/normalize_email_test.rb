require "test_helper"

class Studio::Auth::NormalizeEmailTest < ActiveSupport::TestCase
  test "folds what Arabic, Persian and Thai keyboards type to the plain address" do
    {
      "ＣＯＯＫ＠studio.com" => "cook@studio.com",
      "cook٠١٢٣٤٥٦٧٨٩@studio.com" => "cook0123456789@studio.com",
      "cook۰۱۲۳۴۵۶۷۸۹@studio.com" => "cook0123456789@studio.com",
      "cook๐๑๒๓๔๕๖๗๘๙@studio.com" => "cook0123456789@studio.com",
      " ‏Cook​@Stu⁦dio‮.com﻿ " => "cook@studio.com",
      "cook\xFF@studio.com" => "cook@studio.com"
    }.each do |typed, expected|
      assert_equal expected, Studio::Auth.normalize_email(typed), typed.inspect
    end
  end
end
