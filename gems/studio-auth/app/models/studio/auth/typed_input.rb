module Studio
  module Auth
    module TypedInput
      INVISIBLE_MARKS = /[​-‏‪-‮⁦-⁩﻿]/

      class << self
        def email_address(value)
          ascii_digits(value.to_s.scrub("").unicode_normalize(:nfkc))
            .gsub(INVISIBLE_MARKS, "")
            .strip.downcase
        end

        def code(value)
          ascii_digits(value).gsub(/\D/, "")
        end

        private

        def ascii_digits(value)
          value.to_s.scrub("").gsub(/\p{Nd}/) { |digit| ascii_digit(digit) }
        end

        def ascii_digit(digit)
          return digit if digit.ascii_only?

          zero = digit.ord
          zero -= 1 while digit.ord - zero < 9 && (zero - 1).chr(Encoding::UTF_8).match?(/\p{Nd}/)
          (digit.ord - zero).to_s
        end
      end
    end
  end
end
