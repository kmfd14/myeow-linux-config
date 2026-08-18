# SaaS Security Best Practices

## Multi-Tenancy Isolation

### Database-per-Tenant Architecture (Primary Approach)

This application uses **database-per-tenant** architecture for maximum security and isolation.

**Benefits:**
- Complete data isolation at database level
- No risk of cross-tenant data leaks from application bugs
- Performance isolation (one tenant's load doesn't affect others)
- Individual backups and restores per tenant
- Easier regulatory compliance (GDPR, data residency)
- Scalability across multiple database servers
- Database-level encryption and access control

**Implementation with Apartment gem:**
```ruby
# config/initializers/apartment.rb
Apartment.configure do |config|
  # Each tenant gets own database
  config.tenant_names = lambda { Tenant.pluck(:database_name) }
  
  # Central models (excluded from tenant databases)
  config.excluded_models = %w[Tenant Plan AdminUser Feature]
end

# Automatic database switching via subdomain
Rails.application.config.middleware.use Apartment::Elevators::Subdomain
```

**Security Advantages:**
- SQL injection attacks limited to single tenant database
- No accidental cross-tenant queries possible (database isolation)
- Database-level access control and permissions
- Separate connection pools per tenant
- Individual encryption keys per tenant database
- Complete audit trail per tenant

**See references/database-per-tenant.md for complete implementation.**

### UUID Primary Keys (Already Implemented)
```ruby
# config/application.rb or config/initializers/generators.rb
config.generators do |g|
  g.orm :active_record, primary_key_type: :uuid
end
```

### Row-Level Security Patterns

**Option 1: Default Scope (Simple)**
```ruby
class ApplicationRecord < ActiveRecord::Base
  def self.tenant_scoped
    where(tenant_id: Current.tenant_id) if Current.tenant_id
  end
end

class Post < ApplicationRecord
  belongs_to :tenant
  default_scope { tenant_scoped }
end
```

**Option 2: acts_as_tenant Gem (Recommended)**
```ruby
# Gemfile
gem 'acts_as_tenant'

# app/models/tenant.rb
class Tenant < ApplicationRecord
  has_many :users
  has_many :posts
end

# app/models/post.rb
class Post < ApplicationRecord
  acts_as_tenant(:tenant)
end

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  set_current_tenant_through_filter
  before_action :set_tenant
  
  def set_tenant
    set_current_tenant(current_user.tenant)
  end
end
```

### Tenant Isolation Checklist
- [ ] All tenant-scoped models have `belongs_to :tenant`
- [ ] All queries automatically scope to current tenant
- [ ] Admin actions explicitly bypass tenant scope when needed
- [ ] Background jobs include tenant context
- [ ] File uploads isolated by tenant (use tenant_id in path)
- [ ] Cache keys include tenant_id

## Authentication & Authorization

### Devise Configuration
```ruby
# config/initializers/devise.rb
Devise.setup do |config|
  # Use secure password requirements
  config.password_length = 12..128
  
  # Lockable after failed attempts
  config.lock_strategy = :failed_attempts
  config.unlock_strategy = :time
  config.maximum_attempts = 5
  config.unlock_in = 1.hour
  
  # Session timeout
  config.timeout_in = 30.minutes
  
  # Secure remember me
  config.remember_for = 2.weeks
  config.extend_remember_period = true
end
```

### Authorization Pattern (Pundit)
```ruby
# Gemfile
gem 'pundit'

# app/policies/application_policy.rb
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    record.tenant_id == user.tenant_id
  end

  def create?
    user.tenant_id.present?
  end

  def update?
    show? && record.user_id == user.id
  end

  def destroy?
    update?
  end
end

# In controller
class PostsController < ApplicationController
  def show
    @post = Post.find(params[:id])
    authorize @post  # Pundit authorization
  end
end
```

## Data Protection

### Encryption at Rest
```ruby
# Gemfile
gem 'lockbox'

# app/models/user.rb
class User < ApplicationRecord
  encrypts :email, deterministic: true  # Rails 7+
  encrypts :phone_number
  
  # Or use Lockbox for more control
  # encrypts :ssn, key: :encryption_key
end
```

### Sensitive Data Handling
```ruby
# config/initializers/filter_parameter_logging.rb
Rails.application.config.filter_parameters += [
  :password, :password_confirmation,
  :ssn, :credit_card, :cvv,
  :api_key, :api_secret, :token
]
```

## API Security

### Rate Limiting
```ruby
# Gemfile
gem 'rack-attack'

# config/initializers/rack_attack.rb
Rack::Attack.throttle('api/ip', limit: 100, period: 1.hour) do |req|
  req.ip if req.path.start_with?('/api/')
end

Rack::Attack.throttle('login/ip', limit: 5, period: 20.seconds) do |req|
  req.ip if req.path == '/users/sign_in' && req.post?
end
```

### API Authentication (JWT)
```ruby
# Gemfile
gem 'jwt'

# app/controllers/api/base_controller.rb
module Api
  class BaseController < ActionController::API
    before_action :authenticate_api_user
    
    private
    
    def authenticate_api_user
      token = request.headers['Authorization']&.split(' ')&.last
      payload = JWT.decode(token, Rails.application.credentials.secret_key_base).first
      @current_user = User.find(payload['user_id'])
      set_current_tenant(@current_user.tenant)
    rescue JWT::DecodeError
      render json: { error: 'Invalid token' }, status: :unauthorized
    end
  end
end
```

## GDPR & Data Privacy

### Data Export
```ruby
class User < ApplicationRecord
  def export_data
    {
      profile: attributes.except('encrypted_password'),
      posts: posts.select(:id, :title, :created_at),
      comments: comments.select(:id, :content, :created_at)
    }.to_json
  end
end
```

### Right to be Forgotten
```ruby
class User < ApplicationRecord
  def anonymize!
    update!(
      email: "deleted_#{id}@example.com",
      first_name: "Deleted",
      last_name: "User",
      phone: nil,
      deleted_at: Time.current
    )
    # Soft delete associated records or anonymize
  end
end
```

## Secure Headers

```ruby
# config/initializers/secure_headers.rb
SecureHeaders::Configuration.default do |config|
  config.x_frame_options = "DENY"
  config.x_content_type_options = "nosniff"
  config.x_xss_protection = "1; mode=block"
  config.referrer_policy = %w(origin-when-cross-origin strict-origin-when-cross-origin)
  
  config.csp = {
    default_src: %w('self'),
    script_src: %w('self' 'unsafe-inline'),
    style_src: %w('self' 'unsafe-inline'),
    img_src: %w('self' data: https:),
    connect_src: %w('self')
  }
end
```

## Security Monitoring

### Failed Login Attempts
```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :lockable, :timeoutable
  
  after_update :notify_security_team, if: :locked_at_changed?
  
  private
  
  def notify_security_team
    SecurityMailer.account_locked(self).deliver_later if locked_at.present?
  end
end
```

### Audit Logging
```ruby
# Gemfile
gem 'audited'

# app/models/post.rb
class Post < ApplicationRecord
  audited associated_with: :tenant
end

# Query audit trail
post.audits
post.audits.where(action: 'update')
```

## Environment Security

```ruby
# Never commit these
# config/credentials.yml.enc (encrypted)
development:
  secret_key_base: <%= ENV['SECRET_KEY_BASE'] %>
  database_password: <%= ENV['DATABASE_PASSWORD'] %>
  paypal_client_id: <%= ENV['PAYPAL_CLIENT_ID'] %>
  paypal_secret: <%= ENV['PAYPAL_SECRET'] %>
  paymongo_public_key: <%= ENV['PAYMONGO_PUBLIC_KEY'] %>
  paymongo_secret_key: <%= ENV['PAYMONGO_SECRET_KEY'] %>
```

## Payment Security (Philippine Providers)

### PayMongo Integration
```ruby
class PaymongoService
  def initialize(tenant)
    @tenant = tenant
    @api_key = Rails.application.credentials.dig(:paymongo, :secret_key)
  end
  
  def create_payment_intent(amount, description)
    # Always validate amount server-side
    # Never trust client-side amount
    validated_amount = calculate_amount_for(@tenant, description)
    
    # Use PayMongo API with proper error handling
    # Store transaction records for audit
  end
end
```

### Maya (PayMaya) Integration
```ruby
class MayaService
  # Similar pattern: server-side validation
  # Webhook signature verification
  # Transaction logging
end
```
