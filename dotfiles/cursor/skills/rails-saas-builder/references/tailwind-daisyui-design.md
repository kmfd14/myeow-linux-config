# Tailwind CSS & DaisyUI Design Guide

## Setup and Configuration

### Installing Tailwind CSS in Rails 8.1

Rails 8.1 comes with Tailwind CSS pre-configured when using the default setup. If not already installed:

```bash
# Add Tailwind CSS
./bin/bundle add tailwindcss-rails
./bin/rails tailwindcss:install
```

### Installing DaisyUI

```bash
# Install DaisyUI
yarn add -D daisyui@latest

# Or with npm
npm install -D daisyui@latest
```

### Configure Tailwind with DaisyUI

```javascript
// tailwind.config.js
module.exports = {
  content: [
    './app/views/**/*.html.erb',
    './app/helpers/**/*.rb',
    './app/assets/stylesheets/**/*.css',
    './app/javascript/**/*.js'
  ],
  theme: {
    extend: {
      colors: {
        // Add custom brand colors here
        'brand-primary': '#3B82F6',
        'brand-secondary': '#8B5CF6',
      },
    },
  },
  plugins: [
    require('daisyui'),
  ],
  daisyui: {
    themes: [
      {
        mytheme: {
          "primary": "#3B82F6",
          "secondary": "#8B5CF6",
          "accent": "#F59E0B",
          "neutral": "#3D4451",
          "base-100": "#FFFFFF",
          "info": "#3ABFF8",
          "success": "#36D399",
          "warning": "#FBBD23",
          "error": "#F87272",
        },
      },
      "light",
      "dark",
    ],
  },
}
```

### Import in Application CSS

```css
/* app/assets/stylesheets/application.tailwind.css */
@tailwind base;
@tailwind components;
@tailwind utilities;

/* Custom component classes */
@layer components {
  .card-hover {
    @apply transition-all duration-300 hover:shadow-xl hover:-translate-y-1;
  }
  
  .input-primary {
    @apply input input-bordered w-full focus:input-primary;
  }
  
  .btn-custom {
    @apply btn btn-primary normal-case font-semibold;
  }
}
```

## Mobile-First Responsive Design

### Responsive Breakpoints

Tailwind uses mobile-first breakpoints:

```
sm:  640px  (tablets, small laptops)
md:  768px  (tablets landscape, laptops)
lg:  1024px (desktops)
xl:  1280px (large desktops)
2xl: 1536px (extra large screens)
```

### Mobile-First Pattern

```erb
<!-- Start with mobile, scale up -->
<div class="
  grid grid-cols-1          <!-- Mobile: 1 column -->
  sm:grid-cols-2            <!-- Tablet: 2 columns -->
  lg:grid-cols-3            <!-- Desktop: 3 columns -->
  xl:grid-cols-4            <!-- Large: 4 columns -->
  gap-4
">
  <%= render @items %>
</div>

<!-- Responsive padding/margin -->
<div class="
  px-4 py-6                 <!-- Mobile: smaller padding -->
  md:px-8 md:py-12          <!-- Tablet/Desktop: larger padding -->
">
  <h1 class="
    text-2xl                <!-- Mobile: smaller text -->
    md:text-4xl             <!-- Desktop: larger text -->
    font-bold
  ">
    Title
  </h1>
</div>

<!-- Responsive visibility -->
<div class="
  block md:hidden           <!-- Show on mobile only -->
">
  Mobile Menu
</div>

<div class="
  hidden md:block           <!-- Show on desktop only -->
">
  Desktop Navigation
</div>
```

## DaisyUI Components

### Buttons

```erb
<!-- Basic buttons -->
<%= button_to "Submit", path, class: "btn btn-primary" %>
<%= button_to "Cancel", path, class: "btn btn-secondary" %>
<%= button_to "Delete", path, class: "btn btn-error" %>

<!-- Button sizes -->
<%= button_to "Small", path, class: "btn btn-sm btn-primary" %>
<%= button_to "Normal", path, class: "btn btn-primary" %>
<%= button_to "Large", path, class: "btn btn-lg btn-primary" %>

<!-- Button variants -->
<%= button_to "Outline", path, class: "btn btn-outline btn-primary" %>
<%= button_to "Ghost", path, class: "btn btn-ghost" %>
<%= button_to "Link", path, class: "btn btn-link" %>

<!-- Loading state -->
<button class="btn btn-primary" disabled>
  <span class="loading loading-spinner"></span>
  Loading...
</button>

<!-- Responsive button -->
<%= button_to "Action", path, class: "
  btn btn-primary
  btn-sm md:btn-md           <!-- Small on mobile, normal on desktop -->
  w-full sm:w-auto           <!-- Full width mobile, auto desktop -->
" %>
```

### Forms & Inputs

```erb
<!-- Input with DaisyUI -->
<div class="form-control w-full max-w-xs">
  <%= f.label :name, class: "label" do %>
    <span class="label-text">Name</span>
  <% end %>
  <%= f.text_field :name, class: "input input-bordered w-full" %>
  <% if @model.errors[:name].any? %>
    <%= f.label :name, class: "label" do %>
      <span class="label-text-alt text-error">
        <%= @model.errors[:name].first %>
      </span>
    <% end %>
  <% end %>
</div>

<!-- Select dropdown -->
<div class="form-control w-full max-w-xs">
  <%= f.label :status, class: "label" do %>
    <span class="label-text">Status</span>
  <% end %>
  <%= f.select :status, 
      options_for_select([['Active', 'active'], ['Inactive', 'inactive']]),
      {},
      class: "select select-bordered w-full" %>
</div>

<!-- Checkbox -->
<div class="form-control">
  <label class="label cursor-pointer">
    <%= f.check_box :terms, class: "checkbox checkbox-primary" %>
    <span class="label-text ml-2">I agree to terms and conditions</span>
  </label>
</div>

<!-- Radio buttons -->
<div class="form-control">
  <label class="label cursor-pointer">
    <%= f.radio_button :plan, 'starter', class: "radio radio-primary" %>
    <span class="label-text ml-2">Starter Plan</span>
  </label>
  <label class="label cursor-pointer">
    <%= f.radio_button :plan, 'pro', class: "radio radio-primary" %>
    <span class="label-text ml-2">Pro Plan</span>
  </label>
</div>

<!-- Textarea -->
<div class="form-control">
  <%= f.label :description, class: "label" do %>
    <span class="label-text">Description</span>
  <% end %>
  <%= f.text_area :description, 
      rows: 4,
      class: "textarea textarea-bordered h-24" %>
</div>

<!-- Responsive form layout -->
<div class="grid grid-cols-1 md:grid-cols-2 gap-4">
  <div class="form-control">
    <%= f.label :first_name, class: "label" do %>
      <span class="label-text">First Name</span>
    <% end %>
    <%= f.text_field :first_name, class: "input input-bordered w-full" %>
  </div>
  
  <div class="form-control">
    <%= f.label :last_name, class: "label" do %>
      <span class="label-text">Last Name</span>
    <% end %>
    <%= f.text_field :last_name, class: "input input-bordered w-full" %>
  </div>
</div>
```

### Cards

```erb
<!-- Basic card -->
<div class="card bg-base-100 shadow-xl">
  <div class="card-body">
    <h2 class="card-title">Card Title</h2>
    <p>Card content goes here</p>
    <div class="card-actions justify-end">
      <%= link_to "View Details", path, class: "btn btn-primary" %>
    </div>
  </div>
</div>

<!-- Card with image -->
<div class="card bg-base-100 shadow-xl">
  <%= image_tag "placeholder.jpg", class: "rounded-t-lg" %>
  <div class="card-body">
    <h2 class="card-title">Product Name</h2>
    <p>Product description</p>
    <div class="card-actions justify-end">
      <%= button_to "Add to Cart", path, class: "btn btn-primary" %>
    </div>
  </div>
</div>

<!-- Compact card -->
<div class="card card-compact bg-base-100 shadow-xl">
  <div class="card-body">
    <h2 class="card-title">Compact Card</h2>
    <p>Less padding for tighter layouts</p>
  </div>
</div>

<!-- Responsive card grid -->
<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 md:gap-6">
  <% @items.each do |item| %>
    <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
      <div class="card-body">
        <h2 class="card-title text-lg md:text-xl"><%= item.name %></h2>
        <p class="text-sm md:text-base"><%= item.description %></p>
        <div class="card-actions justify-end">
          <%= link_to "View", item, class: "btn btn-sm btn-primary" %>
        </div>
      </div>
    </div>
  <% end %>
</div>
```

### Navigation

```erb
<!-- Navbar -->
<div class="navbar bg-base-100 shadow-lg">
  <div class="navbar-start">
    <!-- Mobile menu button -->
    <div class="dropdown">
      <label tabindex="0" class="btn btn-ghost lg:hidden">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h8m-8 6h16" />
        </svg>
      </label>
      <ul tabindex="0" class="menu menu-sm dropdown-content mt-3 z-[1] p-2 shadow bg-base-100 rounded-box w-52">
        <li><%= link_to "Home", root_path %></li>
        <li><%= link_to "Features", features_path %></li>
        <li><%= link_to "Pricing", pricing_path %></li>
      </ul>
    </div>
    <%= link_to "Brand", root_path, class: "btn btn-ghost normal-case text-xl" %>
  </div>
  
  <!-- Desktop menu -->
  <div class="navbar-center hidden lg:flex">
    <ul class="menu menu-horizontal px-1">
      <li><%= link_to "Home", root_path %></li>
      <li><%= link_to "Features", features_path %></li>
      <li><%= link_to "Pricing", pricing_path %></li>
    </ul>
  </div>
  
  <div class="navbar-end">
    <% if user_signed_in? %>
      <div class="dropdown dropdown-end">
        <label tabindex="0" class="btn btn-ghost btn-circle avatar">
          <div class="w-10 rounded-full">
            <%= image_tag current_user.avatar_url || "default-avatar.png" %>
          </div>
        </label>
        <ul tabindex="0" class="menu menu-sm dropdown-content mt-3 z-[1] p-2 shadow bg-base-100 rounded-box w-52">
          <li><%= link_to "Profile", profile_path %></li>
          <li><%= link_to "Settings", settings_path %></li>
          <li><%= button_to "Logout", destroy_user_session_path, method: :delete %></li>
        </ul>
      </div>
    <% else %>
      <%= link_to "Login", new_user_session_path, class: "btn btn-ghost" %>
      <%= link_to "Sign Up", new_user_registration_path, class: "btn btn-primary" %>
    <% end %>
  </div>
</div>

<!-- Drawer (mobile sidebar) -->
<div class="drawer">
  <input id="my-drawer" type="checkbox" class="drawer-toggle" />
  <div class="drawer-content">
    <!-- Page content -->
    <label for="my-drawer" class="btn btn-primary drawer-button lg:hidden">
      Open Menu
    </label>
  </div>
  <div class="drawer-side">
    <label for="my-drawer" class="drawer-overlay"></label>
    <ul class="menu p-4 w-80 min-h-full bg-base-200 text-base-content">
      <li><%= link_to "Home", root_path %></li>
      <li><%= link_to "Features", features_path %></li>
      <li><%= link_to "Pricing", pricing_path %></li>
    </ul>
  </div>
</div>
```

### Alerts & Notifications

```erb
<!-- Success alert -->
<% if notice %>
  <div class="alert alert-success shadow-lg mb-4">
    <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
    <span><%= notice %></span>
  </div>
<% end %>

<!-- Error alert -->
<% if alert %>
  <div class="alert alert-error shadow-lg mb-4">
    <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
    <span><%= alert %></span>
  </div>
<% end %>

<!-- Toast notification (with Stimulus) -->
<div data-controller="toast" data-toast-message-value="<%= notice %>" class="hidden">
  <div class="toast toast-top toast-end">
    <div class="alert alert-success">
      <span><%= notice %></span>
    </div>
  </div>
</div>
```

### Modal

```erb
<!-- Modal trigger -->
<%= link_to "Open Modal", "#", 
    class: "btn btn-primary",
    data: { action: "click->modal#open" } %>

<!-- Modal structure -->
<div data-controller="modal" class="hidden" data-modal-target="container">
  <input type="checkbox" class="modal-toggle" data-modal-target="toggle" />
  <div class="modal">
    <div class="modal-box relative">
      <label class="btn btn-sm btn-circle absolute right-2 top-2" 
             data-action="click->modal#close">✕</label>
      <h3 class="font-bold text-lg">Modal Title</h3>
      <p class="py-4">Modal content goes here</p>
      <div class="modal-action">
        <%= button_to "Save", path, class: "btn btn-primary" %>
        <button class="btn" data-action="click->modal#close">Cancel</button>
      </div>
    </div>
  </div>
</div>

<!-- Modal with Turbo Frame (recommended for Rails) -->
<%= link_to "Edit", edit_resource_path(@resource),
    data: { turbo_frame: "modal" },
    class: "btn btn-primary" %>

<%= turbo_frame_tag "modal" %>
```

### Tables

```erb
<!-- Responsive table -->
<div class="overflow-x-auto">
  <table class="table table-zebra w-full">
    <thead>
      <tr>
        <th>Name</th>
        <th>Email</th>
        <th class="hidden md:table-cell">Created</th>
        <th>Actions</th>
      </tr>
    </thead>
    <tbody>
      <% @users.each do |user| %>
        <tr>
          <td>
            <div class="flex items-center space-x-3">
              <div class="avatar">
                <div class="mask mask-squircle w-12 h-12">
                  <%= image_tag user.avatar_url || "default-avatar.png" %>
                </div>
              </div>
              <div>
                <div class="font-bold"><%= user.name %></div>
                <div class="text-sm opacity-50 md:hidden"><%= user.email %></div>
              </div>
            </div>
          </td>
          <td class="hidden md:table-cell"><%= user.email %></td>
          <td class="hidden md:table-cell">
            <%= user.created_at.strftime("%b %d, %Y") %>
          </td>
          <td>
            <div class="flex gap-2">
              <%= link_to "Edit", edit_user_path(user), class: "btn btn-ghost btn-xs" %>
              <%= button_to "Delete", user_path(user), 
                  method: :delete,
                  class: "btn btn-ghost btn-xs text-error" %>
            </div>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>

<!-- Compact table for mobile -->
<div class="md:hidden">
  <% @users.each do |user| %>
    <div class="card bg-base-100 shadow-xl mb-4">
      <div class="card-body">
        <h2 class="card-title"><%= user.name %></h2>
        <p class="text-sm"><%= user.email %></p>
        <p class="text-xs text-gray-500">
          <%= user.created_at.strftime("%b %d, %Y") %>
        </p>
        <div class="card-actions justify-end">
          <%= link_to "Edit", edit_user_path(user), class: "btn btn-sm btn-primary" %>
        </div>
      </div>
    </div>
  <% end %>
</div>
```

### Loading States

```erb
<!-- Skeleton loader -->
<div class="flex flex-col gap-4 w-full">
  <div class="skeleton h-32 w-full"></div>
  <div class="skeleton h-4 w-28"></div>
  <div class="skeleton h-4 w-full"></div>
  <div class="skeleton h-4 w-full"></div>
</div>

<!-- Spinner -->
<div class="flex justify-center items-center h-screen">
  <span class="loading loading-spinner loading-lg"></span>
</div>

<!-- Progress bar -->
<progress class="progress progress-primary w-full" value="70" max="100"></progress>
```

### Badges & Tags

```erb
<!-- Status badges -->
<span class="badge badge-success">Active</span>
<span class="badge badge-error">Inactive</span>
<span class="badge badge-warning">Pending</span>
<span class="badge badge-info">Draft</span>

<!-- Sized badges -->
<span class="badge badge-sm badge-primary">Small</span>
<span class="badge badge-md badge-primary">Medium</span>
<span class="badge badge-lg badge-primary">Large</span>

<!-- Outlined badges -->
<span class="badge badge-outline badge-primary">Outlined</span>
```

## Layout Patterns

### Container & Spacing

```erb
<!-- Standard container -->
<div class="container mx-auto px-4 py-8 md:px-8 md:py-12">
  <!-- Content -->
</div>

<!-- Max width container -->
<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
  <!-- Content -->
</div>

<!-- Section spacing -->
<section class="py-12 md:py-20">
  <div class="container mx-auto px-4">
    <!-- Section content -->
  </div>
</section>
```

### Common Page Layouts

```erb
<!-- Dashboard layout -->
<div class="min-h-screen bg-base-200">
  <!-- Header -->
  <div class="navbar bg-base-100 shadow-lg">
    <!-- Navbar content -->
  </div>
  
  <!-- Main content -->
  <div class="container mx-auto px-4 py-8">
    <div class="grid grid-cols-1 lg:grid-cols-4 gap-6">
      <!-- Sidebar (hidden on mobile) -->
      <aside class="hidden lg:block lg:col-span-1">
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <!-- Sidebar navigation -->
          </div>
        </div>
      </aside>
      
      <!-- Main content -->
      <main class="lg:col-span-3">
        <!-- Page content -->
      </main>
    </div>
  </div>
</div>

<!-- Hero section -->
<div class="hero min-h-screen bg-base-200">
  <div class="hero-content text-center">
    <div class="max-w-md">
      <h1 class="text-4xl md:text-5xl font-bold">Hello there</h1>
      <p class="py-6 text-base md:text-lg">
        Provident cupiditate voluptatem et in.
      </p>
      <%= link_to "Get Started", signup_path, class: "btn btn-primary btn-lg" %>
    </div>
  </div>
</div>

<!-- Split layout (form on left, content on right) -->
<div class="grid grid-cols-1 lg:grid-cols-2 min-h-screen">
  <div class="bg-base-100 p-8 lg:p-16 flex items-center justify-center">
    <!-- Form content -->
  </div>
  <div class="bg-primary text-primary-content p-8 lg:p-16 flex items-center justify-center">
    <!-- Marketing content -->
  </div>
</div>
```

## Touch-Friendly Mobile Design

### Minimum Touch Targets

```erb
<!-- Buttons should be at least 44x44px -->
<button class="btn btn-primary min-h-[44px] min-w-[44px]">
  Click Me
</button>

<!-- Links with adequate padding -->
<%= link_to "Link", path, class: "inline-block py-3 px-4 hover:underline" %>

<!-- Icon buttons -->
<button class="btn btn-square btn-lg">
  <svg class="w-6 h-6"><!-- icon --></svg>
</button>
```

### Swipe-Friendly Carousels

```erb
<!-- DaisyUI Carousel -->
<div class="carousel w-full rounded-box">
  <div class="carousel-item w-full">
    <%= image_tag "slide1.jpg", class: "w-full" %>
  </div>
  <div class="carousel-item w-full">
    <%= image_tag "slide2.jpg", class: "w-full" %>
  </div>
</div>
```

### Mobile Form Optimization

```erb
<!-- Use appropriate input types for mobile keyboards -->
<%= f.email_field :email, 
    type: "email",
    class: "input input-bordered w-full",
    placeholder: "email@example.com" %>

<%= f.telephone_field :phone,
    type: "tel",
    class: "input input-bordered w-full",
    placeholder: "+63 912 345 6789" %>

<%= f.number_field :amount,
    type: "number",
    inputmode: "decimal",
    class: "input input-bordered w-full" %>

<!-- Large, easy-to-tap submit buttons -->
<%= f.submit "Submit", class: "btn btn-primary btn-lg w-full mt-4" %>
```

## Dark Mode Support

```erb
<!-- Enable theme switching -->
<div class="dropdown dropdown-end">
  <label tabindex="0" class="btn btn-ghost">
    Theme
  </label>
  <ul tabindex="0" class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-52">
    <li><a data-set-theme="light">Light</a></li>
    <li><a data-set-theme="dark">Dark</a></li>
    <li><a data-set-theme="mytheme">Custom</a></li>
  </ul>
</div>
```

## Accessibility Best Practices

```erb
<!-- Semantic HTML with proper ARIA labels -->
<button class="btn btn-primary" aria-label="Submit form">
  <svg class="w-5 h-5" aria-hidden="true"><!-- icon --></svg>
  Submit
</button>

<!-- Form labels for screen readers -->
<div class="form-control">
  <%= f.label :email, class: "label" do %>
    <span class="label-text">Email address</span>
  <% end %>
  <%= f.email_field :email, 
      class: "input input-bordered",
      required: true,
      aria-describedby: "email-help" %>
  <span id="email-help" class="label-text-alt">
    We'll never share your email.
  </span>
</div>

<!-- Skip to content link -->
<a href="#main-content" class="sr-only focus:not-sr-only focus:absolute focus:z-50 focus:p-4 focus:bg-primary focus:text-primary-content">
  Skip to main content
</a>
```

## Performance Tips

1. **Purge unused CSS**: Tailwind's JIT mode automatically purges unused classes
2. **Minimize custom CSS**: Use Tailwind utilities instead of custom CSS when possible
3. **Lazy load images**: Use `loading="lazy"` attribute
4. **Optimize DaisyUI themes**: Only include themes you actually use

```javascript
// tailwind.config.js
daisyui: {
  themes: ["light", "dark"], // Only include themes you use
}
```

## Common Responsive Patterns

```erb
<!-- Stack on mobile, side-by-side on desktop -->
<div class="flex flex-col md:flex-row gap-4">
  <div class="md:w-1/2">Left</div>
  <div class="md:w-1/2">Right</div>
</div>

<!-- Hide on mobile, show on desktop -->
<div class="hidden md:block">Desktop only content</div>

<!-- Show on mobile, hide on desktop -->
<div class="md:hidden">Mobile only content</div>

<!-- Different layouts for different screens -->
<div class="
  flex flex-col              <!-- Mobile: stack vertically -->
  sm:flex-row sm:flex-wrap   <!-- Tablet: row with wrap -->
  lg:grid lg:grid-cols-3     <!-- Desktop: 3-column grid -->
  gap-4
">
  <div>Item 1</div>
  <div>Item 2</div>
  <div>Item 3</div>
</div>
```
