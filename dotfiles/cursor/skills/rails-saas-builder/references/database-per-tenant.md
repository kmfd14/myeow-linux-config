# Database-per-Tenant Multi-Tenancy Architecture

## Overview

Database-per-tenant architecture provides the highest level of data isolation, security, and scalability for large SaaS applications. Each tenant gets their own dedicated PostgreSQL database.

**Benefits:**
- **Maximum security**: Complete data isolation between tenants
- **Performance isolation**: One tenant's load doesn't affect others
- **Easy backup/restore**: Per-tenant database backups
- **Regulatory compliance**: Easier to meet data residency requirements
- **Scalability**: Distribute databases across multiple servers
- **Customization**: Individual schema changes per tenant if needed

**Trade-offs:**
- More complex setup and management
- More databases to maintain
- Connection pool management required

## Setup and Configuration

### 1. Database Configuration

```yaml
# config/database.yml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  host: <%= ENV.fetch("DATABASE_HOST") { "localhost" } %>
  username: <%= ENV.fetch("DATABASE_USERNAME") { "postgres" } %>
  password: <%= ENV.fetch("DATABASE_PASSWORD") { "" } %>

development:
  <<: *default
  # Central database for managing tenants
  database: myapp_central_development

test:
  <<: *default
  database: myapp_central_test

production:
  <<: *default
  database: myapp_central_production
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 20 } %>
```

### 2. Apartment Gem (Recommended)

```ruby
# Gemfile
gem 'apartment'
gem 'apartment-postgresql_schemas', group: :development  # For schema-based alternative
```

```bash
bundle install
rails generate apartment:install
```

### 3. Apartment Configuration

```ruby
# config/initializers/apartment.rb
require 'apartment/elevators/subdomain'

Apartment.configure do |config|
  # Database names will be: tenant_slug (e.g., acme_corp, widget_inc)
  config.tenant_names = lambda { Tenant.pluck(:database_name) }
  
  # Exclude models from tenant databases (they live in central/public schema)
  config.excluded_models = %w[
    Tenant
    AdminUser
    Plan
    Feature
  ]
  
  # Use PostgreSQL databases (each tenant gets own database)
  config.use_schemas = false  # Set to true for schema-based approach
  
  # Database prefix (optional)
  config.database_names = lambda { |tenant_name| "myapp_#{tenant_name}_#{Rails.env}" }
  
  # Parallel migrations for faster deployment
  config.parallel_migration_threads = 4
end

# Middleware to switch databases based on subdomain
Rails.application.config.middleware.use Apartment::Elevators::Subdomain
```

## Database Structure

### Central Database (myapp_central_production)

The central database stores:
- **Tenants**: List of all tenants and their database connections
- **Plans**: Subscription plans
- **Global configuration**: Features, settings
- **Admin users**: Super admin accounts
- **Billing**: Centralized billing records (optional)

```ruby
# db/migrate/XXXXXX_create_tenants.rb (Central DB)
class CreateTenants < ActiveRecord::Migration[8.1]
  def change
    create_table :tenants, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false  # URL subdomain
      t.string :database_name, null: false  # Database identifier
      t.string :status, null: false, default: 'active'
      
      # Contact info
      t.string :email, null: false
      t.string :phone
      
      # Subscription
      t.references :plan, type: :uuid, foreign_key: true
      t.date :trial_ends_at
      t.date :subscription_ends_at
      
      # Database connection info (if distributed)
      t.string :database_host  # For multi-server setups
      t.integer :database_port, default: 5432
      
      # Settings
      t.jsonb :settings, default: {}
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    
    add_index :tenants, :slug, unique: true
    add_index :tenants, :database_name, unique: true
    add_index :tenants, :status
  end
end

# db/migrate/XXXXXX_create_plans.rb (Central DB)
class CreatePlans < ActiveRecord::Migration[8.1]
  def change
    create_table :plans, id: :uuid do |t|
      t.string :name, null: false
      t.decimal :price, precision: 10, scale: 2, null: false
      t.string :billing_period, null: false  # monthly, yearly
      t.jsonb :features, default: {}
      t.integer :max_users
      t.integer :max_storage_gb
      t.boolean :active, default: true
      
      t.timestamps
    end
    
    add_index :plans, :name, unique: true
  end
end
```

### Tenant Databases (myapp_{tenant_slug}_production)

Each tenant database contains:
- **Users**: Tenant's users
- **Application data**: All business logic tables
- **No cross-tenant data**: Complete isolation

```ruby
# db/migrate/XXXXXX_create_users.rb (Tenant DB)
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid do |t|
      # Devise fields
      t.string :email, null: false
      t.string :encrypted_password, null: false
      
      # Profile
      t.string :first_name
      t.string :last_name
      t.string :role, default: 'member'
      
      # Devise modules
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at
      t.integer :sign_in_count, default: 0
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string :current_sign_in_ip
      t.string :last_sign_in_ip
      
      t.timestamps
    end
    
    add_index :users, :email, unique: true
    add_index :users, :reset_password_token, unique: true
  end
end

# All other application tables (Posts, Projects, Tasks, etc.)
# Note: NO tenant_id column needed - database isolation provides it!
```

## Models

### Central Database Models

```ruby
# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end

# app/models/tenant.rb
class Tenant < ApplicationRecord
  # Belongs to central database
  self.abstract_class = false
  
  belongs_to :plan, optional: true
  
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, 
            format: { with: /\A[a-z0-9-]+\z/, message: "only lowercase letters, numbers, and hyphens" }
  validates :database_name, presence: true, uniqueness: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  
  enum status: {
    trial: 'trial',
    active: 'active',
    suspended: 'suspended',
    canceled: 'canceled'
  }
  
  before_validation :generate_database_name, on: :create
  after_create :create_tenant_database
  after_destroy :drop_tenant_database
  
  # Switch to this tenant's database
  def switch!
    Apartment::Tenant.switch!(database_name)
  end
  
  # Check if tenant database exists
  def database_exists?
    ActiveRecord::Base.connection.execute(
      "SELECT 1 FROM pg_database WHERE datname = '#{full_database_name}'"
    ).count > 0
  end
  
  def full_database_name
    "myapp_#{database_name}_#{Rails.env}"
  end
  
  private
  
  def generate_database_name
    self.database_name ||= slug.gsub('-', '_')
  end
  
  def create_tenant_database
    CreateTenantDatabaseJob.perform_later(id)
  end
  
  def drop_tenant_database
    DropTenantDatabaseJob.perform_later(database_name)
  end
end

# app/models/plan.rb
class Plan < ApplicationRecord
  has_many :tenants
  
  validates :name, presence: true, uniqueness: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :billing_period, presence: true, inclusion: { in: %w[monthly yearly] }
end
```

### Tenant Database Models

```ruby
# app/models/user.rb
class User < ApplicationRecord
  # This model exists in each tenant database
  # NO tenant_id needed - database isolation provides security
  
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable, :lockable, :timeoutable
  
  has_many :posts, dependent: :destroy
  has_many :comments, dependent: :destroy
  
  enum role: {
    member: 'member',
    manager: 'manager',
    admin: 'admin'
  }
  
  validates :email, presence: true, uniqueness: true
  validates :role, presence: true
  
  def admin?
    role == 'admin'
  end
end

# app/models/post.rb
class Post < ApplicationRecord
  # Exists in tenant database only
  # NO tenant_id column needed!
  
  belongs_to :user
  has_many :comments, dependent: :destroy
  
  validates :title, presence: true
  validates :content, presence: true
  
  scope :published, -> { where(published: true) }
  scope :recent, -> { order(created_at: :desc) }
end
```

## Tenant Provisioning

### Create New Tenant

```ruby
# app/services/tenant_provisioning_service.rb
class TenantProvisioningService
  def initialize(params)
    @params = params
  end
  
  def call
    ActiveRecord::Base.transaction do
      # 1. Create tenant record in central database
      tenant = create_tenant
      
      # 2. Create database for tenant (async)
      CreateTenantDatabaseJob.perform_later(tenant.id)
      
      # 3. Send welcome email
      TenantMailer.welcome(tenant).deliver_later
      
      tenant
    end
  rescue => e
    Rails.logger.error("Tenant provisioning failed: #{e.message}")
    raise
  end
  
  private
  
  def create_tenant
    Tenant.create!(
      name: @params[:name],
      slug: @params[:slug],
      email: @params[:email],
      plan_id: @params[:plan_id],
      trial_ends_at: 14.days.from_now,
      status: 'trial'
    )
  end
end

# app/jobs/create_tenant_database_job.rb
class CreateTenantDatabaseJob < ApplicationJob
  queue_as :critical
  
  def perform(tenant_id)
    tenant = Tenant.find(tenant_id)
    
    # 1. Create the database
    Apartment::Tenant.create(tenant.database_name)
    
    # 2. Run migrations
    Apartment::Tenant.switch!(tenant.database_name) do
      ActiveRecord::Migrator.migrate(ActiveRecord::Migrator.migrations_paths)
    end
    
    # 3. Seed initial data
    seed_tenant_database(tenant)
    
    # 4. Create initial admin user
    create_admin_user(tenant)
    
    Rails.logger.info("Successfully created database for tenant: #{tenant.slug}")
  rescue => e
    Rails.logger.error("Failed to create database for tenant #{tenant_id}: #{e.message}")
    tenant.update(status: 'suspended')
    TenantMailer.provisioning_failed(tenant).deliver_now
    raise
  end
  
  private
  
  def seed_tenant_database(tenant)
    Apartment::Tenant.switch!(tenant.database_name) do
      # Create default data for new tenant
      # e.g., default categories, templates, etc.
    end
  end
  
  def create_admin_user(tenant)
    Apartment::Tenant.switch!(tenant.database_name) do
      User.create!(
        email: tenant.email,
        password: SecureRandom.hex(16),
        role: 'admin',
        first_name: 'Admin'
      )
    end
  end
end

# app/jobs/drop_tenant_database_job.rb
class DropTenantDatabaseJob < ApplicationJob
  queue_as :critical
  
  def perform(database_name)
    # Create backup before dropping
    BackupTenantDatabaseJob.perform_now(database_name)
    
    # Drop the database
    Apartment::Tenant.drop(database_name)
    
    Rails.logger.info("Successfully dropped database: #{database_name}")
  rescue => e
    Rails.logger.error("Failed to drop database #{database_name}: #{e.message}")
    raise
  end
end
```

## Request Handling

### Subdomain-based Tenant Switching

```ruby
# config/initializers/apartment.rb (already shown above)
Rails.application.config.middleware.use Apartment::Elevators::Subdomain

# This automatically switches to the tenant database based on subdomain:
# acme.myapp.com -> switches to myapp_acme_production database
# widget.myapp.com -> switches to myapp_widget_production database
```

### Custom Domain Support (Optional)

```ruby
# app/middleware/custom_domain_elevator.rb
class CustomDomainElevator
  def initialize(app)
    @app = app
  end
  
  def call(env)
    request = ActionDispatch::Request.new(env)
    host = request.host
    
    # Check if custom domain
    tenant = Tenant.find_by(custom_domain: host)
    
    if tenant
      Apartment::Tenant.switch!(tenant.database_name)
    else
      # Fall back to subdomain
      Apartment::Elevators::Subdomain.new(@app).call(env)
    end
    
    @app.call(env)
  end
end

# config/application.rb
config.middleware.use CustomDomainElevator
```

## Controllers

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :verify_tenant
  
  # Current tenant is automatically set by Apartment middleware
  def current_tenant
    @current_tenant ||= Tenant.find_by(database_name: Apartment::Tenant.current)
  end
  helper_method :current_tenant
  
  private
  
  def verify_tenant
    unless Apartment::Tenant.current.present?
      redirect_to root_url(subdomain: 'www'), alert: 'Invalid tenant'
    end
  end
end

# app/controllers/users_controller.rb
class UsersController < ApplicationController
  # All queries automatically scoped to current tenant's database
  # NO need for tenant_id filtering!
  
  def index
    @users = User.all  # Only users in current tenant's database
  end
  
  def show
    @user = User.find(params[:id])  # Automatically scoped to tenant DB
  end
end
```

## Migrations

### Central Database Migrations

```bash
# Run migrations on central database
rails db:migrate

# This affects only the central database (tenants, plans, etc.)
```

### Tenant Database Migrations

```bash
# Run migrations on all tenant databases
rails apartment:migrate

# Run on specific tenant
rails apartment:migrate TENANT=acme_corp

# Parallel migration (faster)
rails apartment:migrate:parallel
```

### Migration Example

```ruby
# db/migrate/XXXXXX_add_profile_to_users.rb
class AddProfileToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :avatar_url, :string
    add_column :users, :bio, :text
    add_column :users, :timezone, :string, default: 'UTC'
  end
end

# Run with: rails apartment:migrate
# This runs on ALL tenant databases automatically
```

## Background Jobs

```ruby
# app/jobs/application_job.rb
class ApplicationJob < ActiveJob::Base
  around_perform :switch_tenant
  
  private
  
  def switch_tenant
    if arguments.first.is_a?(Hash) && arguments.first[:tenant_database_name]
      Apartment::Tenant.switch!(arguments.first[:tenant_database_name]) do
        yield
      end
    else
      yield
    end
  end
end

# app/jobs/send_report_job.rb
class SendReportJob < ApplicationJob
  queue_as :default
  
  def perform(user_id, tenant_database_name:)
    # Automatically switches to tenant database
    user = User.find(user_id)
    # Generate and send report
  end
end

# Usage:
SendReportJob.perform_later(user.id, tenant_database_name: Apartment::Tenant.current)
```

## Database Backups

```ruby
# app/jobs/backup_tenant_database_job.rb
class BackupTenantDatabaseJob < ApplicationJob
  queue_as :default
  
  def perform(database_name)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    backup_file = "#{Rails.root}/backups/#{database_name}_#{timestamp}.sql.gz"
    
    # Create backup directory
    FileUtils.mkdir_p("#{Rails.root}/backups")
    
    # Dump database
    system("pg_dump -h #{db_host} -U #{db_user} #{full_db_name} | gzip > #{backup_file}")
    
    # Upload to S3 or cloud storage
    upload_to_cloud_storage(backup_file)
    
    # Clean up local file
    File.delete(backup_file)
    
    Rails.logger.info("Backup completed for #{database_name}")
  end
  
  private
  
  def full_db_name
    "myapp_#{database_name}_#{Rails.env}"
  end
  
  def upload_to_cloud_storage(file)
    # Implementation depends on your cloud provider
  end
end

# Schedule daily backups for all tenants
# config/schedule.rb (with whenever gem)
every 1.day, at: '2:00 am' do
  runner "Tenant.active.find_each { |t| BackupTenantDatabaseJob.perform_later(t.database_name) }"
end
```

## Connection Pool Management

```ruby
# config/database.yml
production:
  <<: *default
  database: myapp_central_production
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 20 } %>
  # Important: Set reasonable pool size
  # pool_size = (max_connections / number_of_tenants) / number_of_servers
```

## Testing

```ruby
# test/test_helper.rb
class ActiveSupport::TestCase
  setup do
    # Switch to test tenant database
    Apartment::Tenant.switch!('test_tenant')
  end
  
  teardown do
    # Clean up
    Apartment::Tenant.switch!('public')
  end
end

# test/models/user_test.rb
require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test "should create user in tenant database" do
    # Automatically in test_tenant database
    user = User.create!(email: 'test@example.com', password: 'password')
    assert user.persisted?
    
    # Verify isolation - user doesn't exist in other databases
    Apartment::Tenant.switch!('another_tenant') do
      assert_nil User.find_by(email: 'test@example.com')
    end
  end
end
```

## Performance Optimization

### Connection Pooling

```ruby
# config/initializers/apartment.rb
Apartment.configure do |config|
  # Use connection pool for better performance
  config.persistent_schemas = %w[public shared_extensions]
  
  # Parallel migrations
  config.parallel_migration_threads = 4
end
```

### Database Sharding (Advanced)

```ruby
# For very large deployments, distribute tenants across multiple database servers

# app/models/tenant.rb
class Tenant < ApplicationRecord
  # Assign tenants to different database servers
  def database_config
    {
      adapter: 'postgresql',
      host: database_host || ENV['DATABASE_HOST'],
      port: database_port || 5432,
      database: full_database_name,
      username: ENV['DATABASE_USERNAME'],
      password: ENV['DATABASE_PASSWORD']
    }
  end
end
```

## Monitoring

```ruby
# app/models/concerns/tenant_metrics.rb
module TenantMetrics
  extend ActiveSupport::Concern
  
  included do
    after_create :track_tenant_created
    after_update :track_tenant_updated
  end
  
  def database_size
    result = ActiveRecord::Base.connection.execute(
      "SELECT pg_database_size('#{full_database_name}') as size"
    )
    result.first['size'].to_i / 1024 / 1024  # Convert to MB
  end
  
  def connection_count
    Apartment::Tenant.switch!(database_name) do
      ActiveRecord::Base.connection.execute(
        "SELECT count(*) FROM pg_stat_activity WHERE datname = '#{full_database_name}'"
      ).first['count']
    end
  end
  
  private
  
  def track_tenant_created
    # Send to analytics service
  end
  
  def track_tenant_updated
    # Send to analytics service
  end
end
```

## Security Considerations

1. **No Cross-Database Queries**: Complete isolation prevents SQL injection across tenants
2. **Separate Backups**: Each tenant can be backed up independently
3. **Granular Access Control**: Database-level permissions per tenant
4. **Audit Trail**: Easier to track changes per tenant
5. **Compliance**: Easier to meet GDPR, data residency requirements

## Common Pitfalls

1. **Forgetting to Switch**: Always ensure you're in correct tenant context
2. **Connection Leaks**: Monitor connection pools carefully
3. **Migration Failures**: Test migrations on staging tenants first
4. **Backup Size**: Monitor disk space for backups
5. **Shared Resources**: Keep truly shared data (plans, features) in central DB only

## Deployment Checklist

- [ ] Central database created and migrated
- [ ] Apartment gem configured
- [ ] Tenant provisioning service tested
- [ ] Background job processing configured
- [ ] Backup strategy implemented
- [ ] Connection pool limits set appropriately
- [ ] Monitoring in place
- [ ] Test tenant created and working
- [ ] Subdomain routing configured
- [ ] SSL certificates for subdomains
