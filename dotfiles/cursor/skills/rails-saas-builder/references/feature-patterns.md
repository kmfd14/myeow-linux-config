# Feature Implementation Patterns

## Implementation Workflow

### Phase 1: Analysis & Planning
1. Review existing codebase structure
2. Identify affected models, controllers, views
3. Check database schema for required changes
4. Ask clarifying questions about implementation preferences
5. Propose implementation plan

### Phase 2: Database Design
1. Design migrations with proper indexes
2. Ensure multi-tenancy support
3. Add foreign key constraints
4. Create UUID primary keys
5. Add timestamps and soft deletes if needed

### Phase 3: Backend Implementation
1. Generate/update models with associations
2. Add validations and business logic
3. Create service objects for complex logic
4. Implement background jobs if needed
5. Add API endpoints if required

### Phase 4: Frontend Implementation
1. Create/update views with Hotwire
2. Add Stimulus controllers for interactivity
3. Ensure mobile responsiveness
4. Add proper error handling

### Phase 5: Testing & Deployment
1. Write tests for critical paths
2. Manual testing in development
3. Create Podman test environment
4. Deploy to production

## Common Feature Patterns

### Subscription Billing Implementation

#### Database Schema
```ruby
# db/migrate/XXXXXX_create_subscriptions.rb
class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions, id: :uuid do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true, index: true
      t.references :user, type: :uuid, null: false, foreign_key: true, index: true
      
      t.string :plan_name, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, default: 'PHP', null: false
      t.string :status, null: false, default: 'active'
      t.string :payment_provider # paymongo, maya, paypal
      t.string :external_subscription_id
      
      t.date :current_period_start
      t.date :current_period_end
      t.date :trial_ends_at
      t.date :canceled_at
      
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    
    add_index :subscriptions, :status
    add_index :subscriptions, :external_subscription_id
    add_index :subscriptions, [:tenant_id, :status]
  end
end

# db/migrate/XXXXXX_create_payments.rb
class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments, id: :uuid do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true, index: true
      t.references :subscription, type: :uuid, null: false, foreign_key: true, index: true
      t.references :user, type: :uuid, null: false, foreign_key: true, index: true
      
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, default: 'PHP', null: false
      t.string :status, null: false
      t.string :payment_provider
      t.string :external_payment_id
      
      t.datetime :paid_at
      t.string :payment_method
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    
    add_index :payments, :status
    add_index :payments, :external_payment_id
    add_index :payments, [:tenant_id, :created_at]
  end
end
```

#### Models
```ruby
# app/models/subscription.rb
class Subscription < ApplicationRecord
  acts_as_tenant(:tenant)
  
  belongs_to :tenant
  belongs_to :user
  has_many :payments, dependent: :destroy
  
  enum status: {
    active: 'active',
    past_due: 'past_due',
    canceled: 'canceled',
    incomplete: 'incomplete',
    trialing: 'trialing'
  }
  
  validates :plan_name, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :payment_provider, presence: true, inclusion: { 
    in: %w[paymongo maya paypal] 
  }
  
  scope :active_subscriptions, -> { where(status: 'active') }
  scope :expiring_soon, -> { 
    where(status: 'active')
    .where('current_period_end <= ?', 7.days.from_now)
  }
  
  def active?
    status == 'active' && current_period_end >= Date.today
  end
  
  def cancel!
    update!(status: 'canceled', canceled_at: Time.current)
    # Call payment provider API to cancel
    CancelSubscriptionJob.perform_later(id)
  end
  
  def renew!
    # Call payment provider to process payment
    ProcessSubscriptionRenewalJob.perform_later(id)
  end
end

# app/models/payment.rb
class Payment < ApplicationRecord
  acts_as_tenant(:tenant)
  
  belongs_to :tenant
  belongs_to :subscription
  belongs_to :user
  
  enum status: {
    pending: 'pending',
    succeeded: 'succeeded',
    failed: 'failed',
    refunded: 'refunded'
  }
  
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payment_provider, presence: true
  
  scope :successful, -> { where(status: 'succeeded') }
  scope :recent, -> { order(created_at: :desc) }
end
```

#### Service Objects
```ruby
# app/services/subscription_service.rb
class SubscriptionService
  def initialize(user, params)
    @user = user
    @tenant = user.tenant
    @params = params
  end
  
  def create_subscription
    ActiveRecord::Base.transaction do
      # 1. Create subscription record
      subscription = @tenant.subscriptions.create!(
        user: @user,
        plan_name: @params[:plan_name],
        amount: calculate_amount(@params[:plan_name]),
        currency: @params[:currency] || 'PHP',
        payment_provider: @params[:payment_provider],
        status: 'incomplete'
      )
      
      # 2. Create payment intent with provider
      payment_intent = create_payment_intent(subscription)
      
      # 3. Update subscription with external ID
      subscription.update!(
        external_subscription_id: payment_intent.id,
        current_period_start: Date.today,
        current_period_end: Date.today + 1.month
      )
      
      subscription
    end
  rescue => e
    Rails.logger.error("Subscription creation failed: #{e.message}")
    raise
  end
  
  private
  
  def calculate_amount(plan_name)
    PLANS[plan_name][:amount]
  end
  
  def create_payment_intent(subscription)
    provider_service = payment_provider_service(subscription.payment_provider)
    provider_service.create_payment_intent(
      amount: subscription.amount,
      currency: subscription.currency,
      metadata: {
        subscription_id: subscription.id,
        tenant_id: @tenant.id,
        user_id: @user.id
      }
    )
  end
  
  def payment_provider_service(provider)
    case provider
    when 'paymongo'
      PaymongoService.new
    when 'maya'
      MayaService.new
    when 'paypal'
      PaypalService.new
    else
      raise "Unknown payment provider: #{provider}"
    end
  end
  
  PLANS = {
    'starter' => { amount: 999, features: [] },
    'pro' => { amount: 2999, features: [] },
    'enterprise' => { amount: 9999, features: [] }
  }.freeze
end
```

#### Background Jobs
```ruby
# app/jobs/process_subscription_renewal_job.rb
class ProcessSubscriptionRenewalJob < ApplicationJob
  queue_as :default
  
  def perform(subscription_id)
    subscription = Subscription.find(subscription_id)
    
    # Attempt payment
    payment = Payment.create!(
      tenant: subscription.tenant,
      subscription: subscription,
      user: subscription.user,
      amount: subscription.amount,
      currency: subscription.currency,
      payment_provider: subscription.payment_provider,
      status: 'pending'
    )
    
    provider_service = payment_provider_service(subscription.payment_provider)
    result = provider_service.charge(subscription, payment)
    
    if result.success?
      payment.update!(status: 'succeeded', paid_at: Time.current)
      subscription.update!(
        current_period_start: subscription.current_period_end,
        current_period_end: subscription.current_period_end + 1.month
      )
      SubscriptionMailer.renewal_success(subscription).deliver_later
    else
      payment.update!(status: 'failed')
      subscription.update!(status: 'past_due')
      SubscriptionMailer.renewal_failed(subscription).deliver_later
    end
  end
  
  private
  
  def payment_provider_service(provider)
    "#{provider.camelize}Service".constantize.new
  end
end
```

#### Controllers
```ruby
# app/controllers/subscriptions_controller.rb
class SubscriptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_subscription, only: [:show, :cancel]
  
  def index
    @subscriptions = current_tenant.subscriptions
                                    .includes(:user)
                                    .order(created_at: :desc)
    authorize @subscriptions
  end
  
  def show
    authorize @subscription
  end
  
  def new
    @subscription = Subscription.new
    authorize @subscription
  end
  
  def create
    service = SubscriptionService.new(current_user, subscription_params)
    @subscription = service.create_subscription
    
    authorize @subscription
    
    respond_to do |format|
      format.html { redirect_to @subscription, notice: 'Subscription created successfully.' }
      format.turbo_stream
    end
  rescue => e
    respond_to do |format|
      format.html { 
        flash.now[:alert] = "Error creating subscription: #{e.message}"
        render :new, status: :unprocessable_entity 
      }
      format.turbo_stream { 
        render turbo_stream: turbo_stream.replace(
          'subscription_form',
          partial: 'subscriptions/form',
          locals: { subscription: @subscription, error: e.message }
        )
      }
    end
  end
  
  def cancel
    authorize @subscription
    @subscription.cancel!
    
    respond_to do |format|
      format.html { redirect_to subscriptions_path, notice: 'Subscription canceled.' }
      format.turbo_stream
    end
  end
  
  private
  
  def set_subscription
    @subscription = current_tenant.subscriptions.find(params[:id])
  end
  
  def subscription_params
    params.require(:subscription).permit(:plan_name, :payment_provider, :currency)
  end
end

# app/controllers/webhooks/paymongo_controller.rb
class Webhooks::PaymongoController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_webhook_signature
  
  def create
    event = JSON.parse(request.body.read)
    
    case event['data']['attributes']['type']
    when 'payment.paid'
      handle_payment_paid(event)
    when 'payment.failed'
      handle_payment_failed(event)
    end
    
    head :ok
  end
  
  private
  
  def verify_webhook_signature
    # Verify PayMongo webhook signature
    signature = request.headers['PayMongo-Signature']
    # Verification logic here
  end
  
  def handle_payment_paid(event)
    external_id = event['data']['id']
    payment = Payment.find_by(external_payment_id: external_id)
    payment&.update!(status: 'succeeded', paid_at: Time.current)
  end
  
  def handle_payment_failed(event)
    external_id = event['data']['id']
    payment = Payment.find_by(external_payment_id: external_id)
    payment&.update!(status: 'failed')
  end
end
```

#### Views (Hotwire)
```erb
<!-- app/views/subscriptions/index.html.erb -->
<div class="container mx-auto px-4 py-8">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-3xl font-bold">Subscriptions</h1>
    <%= link_to "New Subscription", new_subscription_path, 
        class: "btn btn-primary",
        data: { turbo_frame: "modal" } %>
  </div>
  
  <%= turbo_frame_tag "subscriptions" do %>
    <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
      <%= render @subscriptions %>
    </div>
  <% end %>
</div>

<!-- app/views/subscriptions/_subscription.html.erb -->
<%= turbo_frame_tag dom_id(subscription) do %>
  <div class="card bg-white shadow-md rounded-lg p-6">
    <div class="flex justify-between items-start mb-4">
      <div>
        <h3 class="text-xl font-semibold"><%= subscription.plan_name.titleize %></h3>
        <p class="text-gray-600">
          <%= number_to_currency(subscription.amount, unit: subscription.currency) %>/month
        </p>
      </div>
      <span class="px-3 py-1 rounded-full text-sm font-semibold
                   <%= subscription.active? ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800' %>">
        <%= subscription.status.titleize %>
      </span>
    </div>
    
    <div class="space-y-2 text-sm text-gray-600">
      <p><strong>Period:</strong> 
        <%= subscription.current_period_start.strftime('%b %d, %Y') %> - 
        <%= subscription.current_period_end.strftime('%b %d, %Y') %>
      </p>
      <p><strong>Provider:</strong> <%= subscription.payment_provider.titleize %></p>
    </div>
    
    <div class="mt-4 flex gap-2">
      <%= link_to "View Details", subscription_path(subscription), 
          class: "btn btn-secondary btn-sm" %>
      <% if subscription.active? %>
        <%= button_to "Cancel", cancel_subscription_path(subscription), 
            method: :patch,
            class: "btn btn-danger btn-sm",
            data: { 
              turbo_confirm: "Are you sure you want to cancel this subscription?",
              turbo_frame: dom_id(subscription)
            } %>
      <% end %>
    </div>
  </div>
<% end %>
```

#### Stimulus Controller
```javascript
// app/javascript/controllers/subscription_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["plan", "amount", "provider"]
  
  connect() {
    console.log("Subscription controller connected")
  }
  
  updateAmount(event) {
    const plan = event.target.value
    const amounts = {
      'starter': '₱999',
      'pro': '₱2,999',
      'enterprise': '₱9,999'
    }
    
    this.amountTarget.textContent = amounts[plan] || '₱0'
  }
  
  selectProvider(event) {
    const provider = event.target.value
    // Update UI based on provider selection
    this.updatePaymentForm(provider)
  }
  
  updatePaymentForm(provider) {
    // Show provider-specific payment fields
    const providerForms = this.element.querySelectorAll('[data-provider]')
    providerForms.forEach(form => {
      form.classList.toggle('hidden', form.dataset.provider !== provider)
    })
  }
}
```

### Admin Panel Implementation

#### Database Schema
```ruby
# db/migrate/XXXXXX_create_admin_users.rb
class CreateAdminUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_users, id: :uuid do |t|
      t.string :email, null: false
      t.string :encrypted_password, null: false
      t.string :role, null: false, default: 'viewer'
      
      t.timestamps
    end
    
    add_index :admin_users, :email, unique: true
    add_index :admin_users, :role
  end
end

# db/migrate/XXXXXX_create_support_requests.rb
class CreateSupportRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :support_requests, id: :uuid do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true, index: true
      t.references :user, type: :uuid, null: false, foreign_key: true, index: true
      t.references :assigned_to, type: :uuid, foreign_key: { to_table: :admin_users }
      
      t.string :subject, null: false
      t.text :description, null: false
      t.string :status, null: false, default: 'open'
      t.string :priority, null: false, default: 'normal'
      t.string :category
      
      t.datetime :resolved_at
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    
    add_index :support_requests, :status
    add_index :support_requests, :priority
    add_index :support_requests, [:tenant_id, :status]
    add_index :support_requests, [:assigned_to_id, :status]
  end
end
```

#### Models
```ruby
# app/models/admin_user.rb
class AdminUser < ApplicationRecord
  devise :database_authenticatable, :lockable, :timeoutable
  
  enum role: {
    viewer: 'viewer',
    support: 'support',
    admin: 'admin',
    super_admin: 'super_admin'
  }
  
  has_many :assigned_requests, 
           class_name: 'SupportRequest', 
           foreign_key: :assigned_to_id
  
  validates :email, presence: true, uniqueness: true
  validates :role, presence: true
  
  def can_manage_users?
    admin? || super_admin?
  end
  
  def can_access_tenant?(tenant)
    super_admin? || admin?
  end
end

# app/models/support_request.rb
class SupportRequest < ApplicationRecord
  acts_as_tenant(:tenant)
  
  belongs_to :tenant
  belongs_to :user
  belongs_to :assigned_to, class_name: 'AdminUser', optional: true
  has_many :comments, dependent: :destroy
  
  enum status: {
    open: 'open',
    in_progress: 'in_progress',
    waiting_customer: 'waiting_customer',
    resolved: 'resolved',
    closed: 'closed'
  }
  
  enum priority: {
    low: 'low',
    normal: 'normal',
    high: 'high',
    urgent: 'urgent'
  }
  
  validates :subject, presence: true
  validates :description, presence: true
  
  scope :unassigned, -> { where(assigned_to_id: nil) }
  scope :my_requests, ->(admin) { where(assigned_to: admin) }
  
  after_create :notify_support_team
  after_update :notify_status_change, if: :saved_change_to_status?
  
  private
  
  def notify_support_team
    SupportMailer.new_request(self).deliver_later
  end
  
  def notify_status_change
    SupportMailer.status_changed(self).deliver_later
  end
end
```

#### Admin Controllers
```ruby
# app/controllers/admin/base_controller.rb
module Admin
  class BaseController < ApplicationController
    before_action :authenticate_admin_user!
    layout 'admin'
    
    private
    
    def authenticate_admin_user!
      unless current_admin_user
        redirect_to admin_login_path, alert: 'Please sign in as admin'
      end
    end
    
    def current_admin_user
      @current_admin_user ||= AdminUser.find_by(id: session[:admin_user_id])
    end
    helper_method :current_admin_user
  end
end

# app/controllers/admin/dashboard_controller.rb
module Admin
  class DashboardController < BaseController
    def index
      @stats = {
        total_tenants: Tenant.count,
        active_subscriptions: Subscription.active_subscriptions.count,
        open_support_requests: SupportRequest.open.count,
        revenue_this_month: Payment.successful
                                    .where('created_at >= ?', Time.current.beginning_of_month)
                                    .sum(:amount)
      }
      
      @recent_signups = Tenant.order(created_at: :desc).limit(10)
      @pending_requests = SupportRequest.unassigned.limit(10)
    end
  end
end

# app/controllers/admin/support_requests_controller.rb
module Admin
  class SupportRequestsController < BaseController
    before_action :set_support_request, only: [:show, :edit, :update, :assign]
    
    def index
      @support_requests = SupportRequest
        .includes(:tenant, :user, :assigned_to)
        .order(created_at: :desc)
        .page(params[:page])
        
      @support_requests = filter_requests(@support_requests)
    end
    
    def show
      @comments = @support_request.comments.order(created_at: :asc)
    end
    
    def update
      if @support_request.update(support_request_params)
        respond_to do |format|
          format.html { redirect_to admin_support_request_path(@support_request) }
          format.turbo_stream
        end
      else
        render :edit, status: :unprocessable_entity
      end
    end
    
    def assign
      @support_request.update!(assigned_to: current_admin_user)
      redirect_to admin_support_request_path(@support_request), 
                  notice: 'Request assigned to you'
    end
    
    private
    
    def set_support_request
      @support_request = SupportRequest.find(params[:id])
    end
    
    def filter_requests(requests)
      requests = requests.where(status: params[:status]) if params[:status].present?
      requests = requests.where(priority: params[:priority]) if params[:priority].present?
      requests = requests.my_requests(current_admin_user) if params[:my_requests]
      requests
    end
    
    def support_request_params
      params.require(:support_request).permit(:status, :priority, :assigned_to_id)
    end
  end
end
```

This covers the main patterns for implementing subscription billing and admin panels. Would you like me to continue with more patterns or move on to creating the main SKILL.md file?
