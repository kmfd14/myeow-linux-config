# Rails Generators Reference

## Philosophy

**Always use Rails generators** to create migrations, models, controllers, and other files. Generators ensure:
- Proper file structure and naming conventions
- Correct timestamps in migrations
- Boilerplate code follows Rails conventions
- Files are created in the right directories
- Less room for human error

## Migration Generators

### Basic Migrations

```bash
# Create a new table
rails generate migration CreateProducts name:string price:decimal description:text

# Add columns to existing table
rails generate migration AddDetailsToProducts sku:string:index stock:integer

# Remove columns
rails generate migration RemoveDescriptionFromProducts description:text

# Add reference/foreign key
rails generate migration AddUserToProducts user:references

# Add index
rails generate migration AddIndexToProductsName
# Then manually add: add_index :products, :name

# Rename column (manually edit the generated file)
rails generate migration RenameProductsNameToTitle
# Edit to add: rename_column :products, :name, :title
```

### Database-per-Tenant Migrations

**Central Database Migrations:**
```bash
# These run ONLY on the central database
# For: Tenant, Plan, AdminUser, global config tables

rails generate migration CreateTenants name:string slug:string:uniq database_name:string:uniq status:string email:string plan:references trial_ends_at:date

rails generate migration CreatePlans name:string:uniq price:decimal billing_period:string max_users:integer active:boolean
```

**Tenant Database Migrations:**
```bash
# These run on ALL tenant databases via: rails apartment:migrate
# For: User, Post, Comment, all application data

# NO tenant_id needed with database-per-tenant!
rails generate migration CreatePosts user:references title:string content:text published:boolean status:string

rails generate migration CreateComments user:references post:references content:text approved:boolean

# Add UUID primary key configuration if not in generators config
rails generate migration EnableUuidExtension
# Edit to add: enable_extension 'pgcrypto'
```

### Migration with Indexes

```bash
# Compound index
rails generate migration AddIndexesToPosts
# Then edit to add:
# add_index :posts, [:user_id, :status]
# add_index :posts, :published

# Unique index
rails generate migration AddEmailIndexToUsers
# Then edit to add:
# add_index :users, :email, unique: true
```

### Migration Best Practices

```bash
# ALWAYS review the generated migration before running
cat db/migrate/XXXXXX_create_posts.rb

# Edit as needed to add:
# - null: false constraints
# - default values
# - proper indexes
# - foreign_key: true on references

# Example edited migration:
class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: true
      t.string :title, null: false
      t.text :content, null: false
      t.boolean :published, default: false, null: false
      t.string :status, default: 'draft', null: false
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    
    # Add custom indexes
    add_index :posts, :status
    add_index :posts, [:user_id, :status]
    add_index :posts, :published
  end
end
```

## Model Generators

### Basic Model Generation

```bash
# Generate model with migrations
rails generate model Product name:string price:decimal description:text sku:string:index stock:integer

# This creates:
# - app/models/product.rb
# - db/migrate/XXXXXX_create_products.rb
# - test/models/product_test.rb
# - test/fixtures/products.yml

# Generate model without migration (when table exists)
rails generate model Product --skip-migration
```

### Central Database Models

```bash
# Models that live in central database
# Add to config/initializers/apartment.rb excluded_models

# Tenant model
rails generate model Tenant name:string slug:string:uniq database_name:string:uniq status:string email:string plan:references

# Plan model
rails generate model Plan name:string:uniq price:decimal billing_period:string max_users:integer

# AdminUser model
rails generate model AdminUser email:string:uniq encrypted_password:string role:string
```

### Tenant Database Models

```bash
# Models that live in each tenant's database
# NO tenant_id reference needed!

# User model (with Devise)
rails generate devise User
# Or without Devise:
rails generate model User email:string:uniq first_name:string last_name:string role:string

# Application models
rails generate model Post user:references title:string content:text published:boolean status:string

rails generate model Comment user:references post:references content:text approved:boolean

rails generate model Project user:references name:string description:text status:string due_date:date

rails generate model Task project:references user:references title:string completed:boolean priority:string
```

### Post-Generation Model Editing

After generating, always edit the model to add:

```ruby
# app/models/post.rb
class Post < ApplicationRecord
  # Associations
  belongs_to :user
  has_many :comments, dependent: :destroy
  
  # Validations
  validates :title, presence: true, length: { maximum: 255 }
  validates :content, presence: true
  validates :status, presence: true, inclusion: { in: %w[draft published archived] }
  
  # Enums
  enum status: {
    draft: 'draft',
    published: 'published',
    archived: 'archived'
  }
  
  # Scopes
  scope :published, -> { where(published: true) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_user, ->(user) { where(user: user) }
  
  # Callbacks (use sparingly)
  before_save :set_published_at
  after_create :notify_followers
  
  private
  
  def set_published_at
    self.published_at = Time.current if published? && published_at.nil?
  end
  
  def notify_followers
    NotifyFollowersJob.perform_later(id, tenant_database_name: Apartment::Tenant.current)
  end
end
```

## Controller Generators

### Standard Controller

```bash
# Generate controller with actions
rails generate controller Posts index show new create edit update destroy

# This creates:
# - app/controllers/posts_controller.rb
# - app/views/posts/ (with view files for each action)
# - test/controllers/posts_controller_test.rb
# - app/helpers/posts_helper.rb

# Generate empty controller
rails generate controller Posts

# Generate API controller
rails generate controller Api::V1::Posts --skip-template-engine
```

### Scaffold Generator (Full CRUD)

```bash
# Generate complete CRUD (model, migration, controller, views)
rails generate scaffold Post user:references title:string content:text published:boolean status:string

# This creates:
# - Model with migration
# - Controller with all CRUD actions
# - Views for index, show, new, edit, _form
# - Routes
# - Tests

# Review and customize the generated code!
```

### Namespaced Controllers

```bash
# Admin namespace
rails generate controller Admin::Posts index show edit update destroy

# API namespace
rails generate controller Api::V1::Posts index show create update destroy --skip-template-engine

# Multiple namespaces
rails generate controller Admin::Reports::Sales index show
```

### Post-Generation Controller Editing

After generating, customize the controller:

```ruby
# app/controllers/posts_controller.rb
class PostsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_post, only: [:show, :edit, :update, :destroy]
  before_action :authorize_post, only: [:edit, :update, :destroy]
  
  def index
    @posts = Post.includes(:user)
                 .published
                 .order(created_at: :desc)
                 .page(params[:page])
  end
  
  def show
    @comments = @post.comments.approved.includes(:user)
  end
  
  def new
    @post = Post.new
  end
  
  def create
    @post = current_user.posts.build(post_params)
    
    respond_to do |format|
      if @post.save
        format.html { redirect_to @post, notice: 'Post created successfully.' }
        format.turbo_stream
      else
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end
  
  def update
    respond_to do |format|
      if @post.update(post_params)
        format.html { redirect_to @post, notice: 'Post updated successfully.' }
        format.turbo_stream
      else
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end
  
  def destroy
    @post.destroy
    
    respond_to do |format|
      format.html { redirect_to posts_url, notice: 'Post deleted.' }
      format.turbo_stream
    end
  end
  
  private
  
  def set_post
    @post = Post.find(params[:id])
  end
  
  def authorize_post
    unless @post.user == current_user || current_user.admin?
      redirect_to posts_path, alert: 'Not authorized'
    end
  end
  
  def post_params
    params.require(:post).permit(:title, :content, :published, :status)
  end
end
```

## Other Useful Generators

### Mailer

```bash
# Generate mailer
rails generate mailer UserMailer welcome password_reset

# Generate with custom template engine
rails generate mailer NotificationMailer new_comment --template-engine=erb
```

### Job (Background)

```bash
# Generate background job
rails generate job SendReport
rails generate job ProcessPayment
rails generate job GenerateInvoice

# Edit to add tenant context:
class SendReportJob < ApplicationJob
  def perform(report_id, tenant_database_name:)
    # Job logic
  end
end
```

### Channel (Action Cable)

```bash
# Generate WebSocket channel
rails generate channel Notifications
rails generate channel Chat
```

### Helper

```bash
# Generate helper
rails generate helper Posts
rails generate helper Application
```

### Service Object (Custom)

```bash
# No built-in generator, but you can create a custom one
# Or manually create:
mkdir -p app/services
touch app/services/posts/create_service.rb
```

### Stimulus Controller

```bash
# Generate Stimulus controller
rails generate stimulus posts
rails generate stimulus dropdown
rails generate stimulus modal

# Creates: app/javascript/controllers/posts_controller.js
```

## Resource Generators

### Full Resource

```bash
# Generate routes, controller, model, views
rails generate resource Post user:references title:string content:text status:string

# This creates everything EXCEPT view templates
# You need to create views manually
```

### API Resource

```bash
# Generate API-only resource
rails generate resource Api::V1::Post user:references title:string content:text --skip-template-engine

# Use for API endpoints
```

## Generator Workflow

### 1. Generate

```bash
# Start with generator
rails generate model Post user:references title:string content:text
```

### 2. Review Migration

```bash
# Check the generated migration
cat db/migrate/XXXXXX_create_posts.rb

# Edit to add constraints, indexes, defaults
```

### 3. Customize Model

```bash
# Open and edit the model
code app/models/post.rb

# Add validations, associations, scopes, enums
```

### 4. Run Migration

```bash
# For central database
rails db:migrate

# For tenant databases
rails apartment:migrate

# Check status
rails db:migrate:status
rails apartment:migrate:status
```

### 5. Generate Controller

```bash
# Generate controller with actions
rails generate controller Posts index show new create edit update destroy
```

### 6. Customize Controller

```bash
# Edit controller
code app/controllers/posts_controller.rb

# Add authentication, authorization, custom logic
```

### 7. Create/Edit Views

```bash
# Views are generated by scaffold or controller generator
# Customize as needed
code app/views/posts/
```

## Database-per-Tenant Generator Workflow

### Creating Central Database Models

```bash
# 1. Generate the model
rails generate model Tenant name:string slug:string database_name:string status:string email:string

# 2. Edit migration (add proper constraints)
# 3. Run central migration
rails db:migrate

# 4. Add to Apartment excluded_models
# config/initializers/apartment.rb
# config.excluded_models = %w[Tenant Plan AdminUser]
```

### Creating Tenant Database Models

```bash
# 1. Generate the model (NO tenant_id!)
rails generate model Post user:references title:string content:text status:string

# 2. Edit migration (add constraints, indexes)

# 3. Run on ALL tenant databases
rails apartment:migrate

# 4. Edit model (validations, associations, scopes)
```

## Testing Generators

### Model Tests

```bash
# Generated automatically with model
# test/models/post_test.rb

require "test_helper"

class PostTest < ActiveSupport::TestCase
  test "should not save without title" do
    post = Post.new
    assert_not post.save
  end
  
  test "should belong to user" do
    post = posts(:one)
    assert_respond_to post, :user
  end
end
```

### Controller Tests

```bash
# Generated with controller
# test/controllers/posts_controller_test.rb

require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
    @post = posts(:one)
  end
  
  test "should get index" do
    get posts_url
    assert_response :success
  end
  
  test "should create post" do
    assert_difference("Post.count") do
      post posts_url, params: { 
        post: { title: "Test", content: "Content", status: "draft" }
      }
    end
    assert_redirected_to post_url(Post.last)
  end
end
```

## Custom Generator (Advanced)

Create your own generators for common patterns:

```bash
# Create custom generator
rails generate generator service

# Creates: lib/generators/service/service_generator.rb
```

```ruby
# lib/generators/service/service_generator.rb
class ServiceGenerator < Rails::Generators::NamedBase
  source_root File.expand_path('templates', __dir__)
  
  def create_service_file
    create_file "app/services/#{file_name}_service.rb", <<~RUBY
      class #{class_name}Service
        def initialize(user, params)
          @user = user
          @params = params
        end
        
        def call
          # Implementation here
        end
      end
    RUBY
  end
end

# Usage:
# rails generate service CreatePost
```

## Generator Options

```bash
# Skip tests
rails generate model Post --skip-test

# Skip fixtures
rails generate model Post --skip-fixture

# Skip migration
rails generate model Post --skip-migration

# Skip routes
rails generate controller Posts --skip-routes

# Skip helper
rails generate controller Posts --skip-helper

# Skip assets
rails generate controller Posts --skip-assets

# Pretend (dry run)
rails generate model Post --pretend

# Force (overwrite existing)
rails generate model Post --force
```

## Destroying Generated Files

```bash
# Undo a generator (deletes files it created)
rails destroy model Post
rails destroy controller Posts
rails destroy migration CreatePosts

# This removes:
# - Generated files
# - Does NOT undo migrations (need to rollback first)
```

## Best Practices

1. **Always generate first**: Use generators before manually creating files
2. **Review before running**: Check generated migrations before `rails db:migrate`
3. **Customize immediately**: Edit models/controllers right after generation
4. **Add constraints**: Update migrations with `null: false`, indexes, foreign keys
5. **Follow conventions**: Let Rails generators guide your file structure
6. **Use --pretend**: Preview what will be generated before committing
7. **Test immediately**: Run tests after generating and customizing

## Quick Reference

```bash
# Migrations
rails g migration CreateProducts name:string price:decimal
rails g migration AddUserToProducts user:references

# Models
rails g model Product name:string price:decimal
rails g devise User  # With Devise

# Controllers
rails g controller Products index show new create
rails g controller Admin::Products --skip-template-engine

# Full CRUD
rails g scaffold Product name:string price:decimal

# Jobs
rails g job ProcessPayment

# Mailers
rails g mailer UserMailer welcome

# Stimulus
rails g stimulus dropdown

# Tests
# Generated automatically with models/controllers
```
