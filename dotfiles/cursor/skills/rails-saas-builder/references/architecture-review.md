# Rails Architecture Review Patterns

## Review Checklist

When analyzing an existing Rails application structure, follow this systematic approach:

### 1. Project Structure Analysis
- Check Rails version and dependencies (Gemfile)
- Identify frontend stack (Hotwire/Stimulus vs React)
- Review database configuration (database.yml)
- Check for Podman/Docker configuration files
- Identify background job setup (Sidekiq, etc.)

### 2. Database Schema Review
```bash
# Always examine these files first
cat db/schema.rb
ls -la db/migrate/
```

Check for:
- UUID as primary keys (should be default)
- Proper indexing on foreign keys and frequently queried columns
- Multi-tenancy implementation (tenant_id columns, row-level security)
- Timestamps (created_at, updated_at)
- Soft deletes (discarded_at, deleted_at)
- Proper constraints (null: false, foreign_key: true)

### 3. Model Layer Review
```bash
# Review all models
ls -la app/models/
```

Check for:
- Associations with proper inverse_of
- Validations (presence, uniqueness, format)
- Scopes for common queries
- Callbacks (minimize side effects)
- Concerns for shared behavior
- Multi-tenancy scoping (default_scope or acts_as_tenant)
- Proper use of enums
- UUID configuration in ApplicationRecord

### 4. Controller Layer Review
```bash
ls -la app/controllers/
```

Check for:
- Thin controllers (logic moved to services/models)
- Proper authentication (before_action :authenticate_user!)
- Authorization checks (CanCanCan, Pundit patterns)
- Multi-tenancy enforcement in every query
- Strong parameters
- Respond_to for different formats
- RESTful action patterns
- Proper error handling

### 5. View Layer Review
```bash
ls -la app/views/
ls -la app/javascript/
```

Check for:
- Partials for reusable components
- Turbo Frames and Streams usage
- Stimulus controllers organization
- Mobile-responsive patterns
- Proper CSRF token handling
- XSS prevention (sanitize, content_tag)

### 6. Service Objects Pattern
```bash
ls -la app/services/
```

Look for complex business logic extracted to:
- app/services/
- app/operations/
- app/interactors/

### 7. Security Review
- Strong parameters in all controllers
- Authentication on sensitive actions
- Authorization checks
- SQL injection prevention (parameterized queries)
- XSS prevention in views
- CSRF protection enabled
- Secure headers configuration
- Environment variables for secrets
- Multi-tenancy isolation verification

### 8. Performance Review
- N+1 query detection (includes, preload, eager_load)
- Database indexes on foreign keys
- Caching strategy (Russian doll caching, fragment caching)
- Background jobs for slow operations
- Asset pipeline optimization
- Database connection pooling

## Common Anti-Patterns to Flag

1. **Fat Controllers**: Business logic in controllers instead of models/services
2. **N+1 Queries**: Missing eager loading
3. **Missing Indexes**: Foreign keys without indexes
4. **Insecure Direct Object References**: No authorization checks
5. **Multi-tenancy Leaks**: Queries without tenant scoping
6. **Callback Hell**: Too many model callbacks
7. **Missing Validations**: Data integrity issues
8. **Hardcoded Values**: Magic numbers/strings instead of constants/configs
