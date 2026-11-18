module Studio
  module Auth
    class EmailAddressChangeForm
      include ActiveModel::Model
      include ActiveModel::Attributes

      attr_accessor :user

      attribute :email_address, :string

      validate :email_address_usable

      def normalized_email_address
        TypedInput.email_address(email_address)
      end

      private

      def email_address_usable
        error = email_address_error
        errors.add(:email_address, error) if error
      end

      def email_address_error
        new_address = normalized_email_address
        return :app_review_account if user.app_review_account?
        return :undeliverable if new_address.blank? || Deliverability.undeliverable?(new_address)
        return :unchanged if new_address == user.email_address
        return :taken if ::User.where.not(id: user.id).exists?(email_address: new_address)

        candidate = ::User.find(user.id)
        candidate.email_address = new_address
        candidate.valid?
        return :staff_email_only if candidate.errors.of_kind?(:staff, :studio_email_only)

        :undeliverable if candidate.errors.include?(:email_address)
      end
    end
  end
end
