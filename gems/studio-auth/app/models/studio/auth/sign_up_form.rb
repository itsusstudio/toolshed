module Studio
  module Auth
    class SignUpForm
      include ActiveModel::Model
      include ActiveModel::Attributes

      FULL_NAME_MAX_LENGTH = 100

      attribute :full_name, :string
      attribute :email_address, :string
      attribute :time_zone, :string

      validates :full_name, presence: true, length: {maximum: FULL_NAME_MAX_LENGTH}

      def full_name=(value)
        super(value.to_s.squish)
      end
    end
  end
end
