namespace :studio_billing do
  desc "Compare the Stripe account with config/billing.yml without changing anything; exits 1 when they differ"
  task check: :environment do
    sync = Studio::Billing::Sync.new
    sync.changes.each { puts "  #{it}" }

    if sync.in_sync?
      puts "Stripe matches config/billing.yml"
    else
      puts "Stripe differs from config/billing.yml. Run studio_billing:sync to apply the changes above."
      exit 1
    end
  end

  desc "Make the Stripe account match config/billing.yml: products, prices, customer portal and webhook endpoint"
  task sync: :environment do
    sync = Studio::Billing::Sync.new
    if sync.in_sync?
      sync.changes.each { puts "  #{it}" }
      next puts("Stripe already matches config/billing.yml")
    end

    result = sync.apply!
    result.changes.each { puts "  #{it}" }
    puts "Stripe now matches config/billing.yml"

    if result.webhook_secret
      if $stdout.tty?
        puts
        puts "New webhook signing secret, shown once. Add it to credentials as stripe.webhook_secret:"
        puts "  #{result.webhook_secret}"
      else
        puts "A new webhook endpoint was created. Its signing secret is only printed in an interactive " \
          "terminal; reveal it in the Stripe Dashboard under Developers, Webhooks."
      end
    end
  end

  desc "Sync every subscription in the Stripe account and reset the event cursor; recovers from a missed hourly run"
  task reconcile_all: :environment do
    count = Studio::Billing::Reconciler.new.reconcile_all
    puts "Synced #{count} Stripe subscriptions"
  end
end
