require "fileutils"
require "shellwords"

# Copied from: https://github.com/mattbrictson/rails-template
# Add this template directory to source_paths so that Thor actions like
# copy_file and template resolve against our source files. If this file was
# invoked remotely via HTTP, that means the files are not present locally.
# In that case, use `git clone` to download them to a local temporary dir.
def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    require "tmpdir"
    source_paths.unshift(tempdir = Dir.mktmpdir("jumpstart-"))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      "--quiet",
      "https://github.com/excid3/jumpstart.git",
      tempdir
    ].map(&:shellescape).join(" ")

    if (branch = __FILE__[%r{jumpstart/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git checkout: branch }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def rails_version
  @rails_version ||= Gem::Version.new(Rails::VERSION::STRING)
end

def rails_6_or_newer?
  Gem::Requirement.new(">= 6.0.0.alpha").satisfied_by? rails_version
end

def add_gems
  add_gem 'cssbundling-rails'
  add_gem 'devise', '~> 4.9'
  add_gem 'friendly_id', '~> 5.4'
  add_gem 'jsbundling-rails'
  add_gem 'madmin'
  add_gem 'name_of_person', '~> 1.1'
  add_gem 'noticed', '~> 1.4'
  add_gem 'omniauth-facebook', '~> 8.0'
  add_gem 'omniauth-github', '~> 2.0'
  add_gem 'omniauth-twitter', '~> 1.4'
  add_gem 'pretender', '~> 0.3.4'
  add_gem 'pundit', '~> 2.1'
  add_gem 'sidekiq', '~> 6.2'
  add_gem 'sitemap_generator', '~> 6.1'
  add_gem 'whenever', require: false
  add_gem 'responders', github: 'heartcombo/responders', branch: 'main'
end

def set_application_name
  # Add Application Name to Config
  environment "config.application_name = Rails.application.class.module_parent_name"

  # Announce the user where they can change the application name in the future.
  puts "You can change application name inside: ./config/application.rb"
end

def add_users
  route "root to: 'home#index'"
  generate "devise:install"

  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }", env: 'development'
  generate :devise, "User", "first_name", "last_name", "announcements_last_read_at:datetime", "admin:boolean"

  # Set admin default to false
  in_root do
    migration = Dir.glob("db/migrate/*").max_by{ |f| File.mtime(f) }
    gsub_file migration, /:admin/, ":admin, default: false"
  end

  if Gem::Requirement.new("> 5.2").satisfied_by? rails_version
    gsub_file "config/initializers/devise.rb", /  # config.secret_key = .+/, "  config.secret_key = Rails.application.credentials.secret_key_base"
  end

  inject_into_file("app/models/user.rb", "omniauthable, :", after: "devise :")
end

def add_authorization
  generate 'pundit:install'
end

def default_to_esbuild
  return if options[:javascript] == "esbuild"
  unless options[:skip_javascript]
    @options = options.merge(javascript: "esbuild")
  end
end

def add_javascript
  run "yarn add local-time esbuild-rails trix @hotwired/stimulus @hotwired/turbo-rails @rails/activestorage @rails/ujs @rails/request.js tailwindcss preline"
end

def copy_templates
  remove_file "app/assets/stylesheets/application.css"
  remove_file "app/javascript/application.js"
  remove_file "app/javascript/controllers/index.js"
  remove_file "Procfile.dev"

  copy_file "Procfile"
  copy_file "Procfile.dev"
  copy_file ".foreman"
  copy_file "esbuild.config.mjs"
  copy_file "app/javascript/application.js"
  copy_file "app/javascript/controllers/index.js"

  directory "app", force: true
  directory "config", force: true
  directory "lib", force: true

  route "get '/terms', to: 'home#terms'"
  route "get '/privacy', to: 'home#privacy'"
end

def add_sidekiq
  environment "config.active_job.queue_adapter = :sidekiq"

  insert_into_file "config/routes.rb",
    "require 'sidekiq/web'\n\n",
    before: "Rails.application.routes.draw do"

  content = <<~RUBY
                authenticate :user, lambda { |u| u.admin? } do
                  mount Sidekiq::Web => '/sidekiq'

                  namespace :madmin do
                    resources :impersonates do
                      post :impersonate, on: :member
                      post :stop_impersonating, on: :collection
                    end
                  end
                end
            RUBY
  insert_into_file "config/routes.rb", "#{content}\n", after: "Rails.application.routes.draw do\n"
end

def add_toastr_helper
  helper = <<~RUBY
              def flash_messages
                capture do
                    flash.each do |key, value|
                    concat tag.div(
                        data: { controller: :flash, flash_key: key, flash_value: value }
                    )
                    end
                end
            RUBY
  insert_into_file "helpers/application_helper.rb", "#{helper}\n", after: "module ApplicationHelper\n"
end

def add_announcements
  generate "model Announcement published_at:datetime announcement_type name description:text"
  route "resources :announcements, only: [:index]"
end

def add_notifications
  route "resources :notifications, only: [:index]"
end

def add_multiple_authentication
  insert_into_file "config/routes.rb", ', controllers: { omniauth_callbacks: "users/omniauth_callbacks" }', after: "  devise_for :users"

  generate "model Service user:references provider uid access_token access_token_secret refresh_token expires_at:datetime auth:text"

  template = """
  env_creds = Rails.application.credentials[Rails.env.to_sym] || {}
  %i{ facebook twitter github }.each do |provider|
    if options = env_creds[provider]
      config.omniauth provider, options[:app_id], options[:app_secret], options.fetch(:options, {})
    end
  end
  """.strip

  insert_into_file "config/initializers/devise.rb", "  " + template + "\n\n", before: "  # ==> Warden configuration"
end

def add_whenever
  run "wheneverize ."
end

def add_friendly_id
  generate "friendly_id"
  insert_into_file( Dir["db/migrate/**/*friendly_id_slugs.rb"].first, "[5.2]", after: "ActiveRecord::Migration")
end

def add_sitemap
  rails_command "sitemap:install"
end

def add_bootstrap
  rails_command "css:install:bootstrap"
end

def add_announcements_css
  insert_into_file 'app/assets/stylesheets/application.scss', '@import "jumpstart/announcements";'
end

def add_tailwind_css
  insert_into_file 'app/assets/stylesheets/application.scss', "@import 'tailwindcss/base';\n@import 'tailwindcss/components';\n@import 'tailwindcss/utilities';" 
end

def add_preline_ui_css
  insert_into_file 'app/assets/stylesheets/application.scss', '@import "~preline-ui/src/preline-ui";'
end

def add_toastr_css
  insert_into_file 'app/assets/stylesheets/application.scss', '@import "toastr/toastr";'
end

def add_esbuild_script
  build_script = "node esbuild.config.mjs"

  case `npx -v`.to_f
  when 7.1...8.0
    run %(npm set-script build "#{build_script}")
    run %(yarn build)
  when (8.0..)
    run %(npm pkg set scripts.build="#{build_script}")
    run %(yarn build)
  else
    say %(Add "scripts": { "build": "#{build_script}" } to your package.json), :green
  end
end

def add_tailwind_config
  template = """
  const defaultTheme = require('tailwindcss/defaultTheme');

  module.exports = {
    theme: {
      extend: {
        fontFamily: {
          sans: ['Montserrat', ...defaultTheme.fontFamily.sans],
        },
        colors: {
          red: {
            '50': '#ffebee',
            '100': '#ffcdd2',
            '200': '#ef9a9a',
            '300': '#e57373',
            '400': '#ef5350',
            '500': '#f44336',
            '600': '#e53935',
            '700': '#d32f2f',
            '800': '#c62828',
            '900': '#b71c1c',
            'accent-100': '#ff8a80',
            'accent-200': '#ff5252',
            'accent-400': '#ff1744',
            'accent-700': '#d50000',
          },
          purple: {
            50: '#f3e5f5',
            100: '#e1bee7',
            200: '#ce93d8',
            300: '#ba68c8',
            400: '#ab47bc',
            500: '#9c27b0',
            600: '#8e24aa',
            700: '#7b1fa2',
            800: '#6a1b9a',
            900: '#4a148c',
            'accent-100': '#ea80fc',
            'accent-200': '#e040fb',
            'accent-400': '#d500f9',
            'accent-700': '#aa00ff',
          },
          'deep-purple': {
            50: '#ede7f6',
            100: '#d1c4e9',
            200: '#b39ddb',
            300: '#9575cd',
            400: '#7e57c2',
            500: '#673ab7',
            600: '#5e35b1',
            700: '#512da8',
            800: '#4527a0',
            900: '#311b92',
            'accent-100': '#b388ff',
            'accent-200': '#7c4dff',
            'accent-400': '#651fff',
            'accent-700': '#6200ea',
          },
          teal: {
            50: '#e0f2f1',
            100: '#b2dfdb',
            200: '#80cbc4',
            300: '#4db6ac',
            400: '#26a69a',
            500: '#009688',
            600: '#00897b',
            700: '#00796b',
            800: '#00695c',
            900: '#004d40',
            'accent-100': '#a7ffeb',
            'accent-200': '#64ffda',
            'accent-400': '#1de9b6',
            'accent-700': '#00bfa5',
          },
          indigo: {
            50: '#e8eaf6',
            100: '#c5cae9',
            200: '#9fa8da',
            300: '#7986cb',
            400: '#5c6bc0',
            500: '#3f51b5',
            600: '#3949ab',
            700: '#303f9f',
            800: '#283593',
            900: '#1a237e',
            'accent-100': '#8c9eff',
            'accent-200': '#536dfe',
            'accent-400': '#3d5afe',
            'accent-700': '#304ffe',
          },
          pink: {
            50: '#fce4ec',
            100: '#f8bbd0',
            200: '#f48fb1',
            300: '#f06292',
            400: '#ec407a',
            500: '#e91e63',
            600: '#d81b60',
            700: '#c2185b',
            800: '#ad1457',
            900: '#880e4f',
            'accent-100': '#ff80ab',
            'accent-200': '#ff4081',
            'accent-400': '#f50057',
            'accent-700': '#c51162',
          },
          blue: {
            50: '#e3f2fd',
            100: '#bbdefb',
            200: '#90caf9',
            300: '#64b5f6',
            400: '#42a5f5',
            500: '#2196f3',
            600: '#1e88e5',
            700: '#1976d2',
            800: '#1565c0',
            900: '#0d47a1',
            'accent-100': '#82b1ff',
            'accent-200': '#448aff',
            'accent-400': '#2979ff',
            'accent-700': '#2962ff',
          },
          'light-blue': {
            50: '#e1f5fe',
            100: '#b3e5fc',
            200: '#81d4fa',
            300: '#4fc3f7',
            400: '#29b6f6',
            500: '#03a9f4',
            600: '#039be5',
            700: '#0288d1',
            800: '#0277bd',
            900: '#01579b',
            'accent-100': '#80d8ff',
            'accent-200': '#40c4ff',
            'accent-400': '#00b0ff',
            'accent-700': '#0091ea',
          },
          cyan: {
            50: '#e0f7fa',
            100: '#b2ebf2',
            200: '#80deea',
            300: '#4dd0e1',
            400: '#26c6da',
            500: '#00bcd4',
            600: '#00acc1',
            700: '#0097a7',
            800: '#00838f',
            900: '#006064',
            'accent-100': '#84ffff',
            'accent-200': '#18ffff',
            'accent-400': '#00e5ff',
            'accent-700': '#00b8d4',
          },
          gray: {
            50: '#fafafa',
            100: '#f5f5f5',
            200: '#eeeeee',
            300: '#e0e0e0',
            400: '#bdbdbd',
            500: '#9e9e9e',
            600: '#757575',
            700: '#616161',
            800: '#424242',
            900: '#212121',
          },
          'blue-gray': {
            50: '#eceff1',
            100: '#cfd8dc',
            200: '#b0bec5',
            300: '#90a4ae',
            400: '#78909c',
            500: '#607d8b',
            600: '#546e7a',
            700: '#455a64',
            800: '#37474f',
            900: '#263238',
          },
          green: {
            50: '#e8f5e9',
            100: '#c8e6c9',
            200: '#a5d6a7',
            300: '#81c784',
            400: '#66bb6a',
            500: '#4caf50',
            600: '#43a047',
            700: '#388e3c',
            800: '#2e7d32',
            900: '#1b5e20',
            'accent-100': '#b9f6ca',
            'accent-200': '#69f0ae',
            'accent-400': '#00e676',
            'accent-700': '#00c853',
          },
          'light-green': {
            50: '#f1f8e9',
            100: '#dcedc8',
            200: '#c5e1a5',
            300: '#aed581',
            400: '#9ccc65',
            500: '#8bc34a',
            600: '#7cb342',
            700: '#689f38',
            800: '#558b2f',
            900: '#33691e',
            'accent-100': '#ccff90',
            'accent-200': '#b2ff59',
            'accent-400': '#76ff03',
            'accent-700': '#64dd17',
          },
          lime: {
            50: '#f9fbe7',
            100: '#f0f4c3',
            200: '#e6ee9c',
            300: '#dce775',
            400: '#d4e157',
            500: '#cddc39',
            600: '#c0ca33',
            700: '#afb42b',
            800: '#9e9d24',
            900: '#827717',
            'accent-100': '#f4ff81',
            'accent-200': '#eeff41',
            'accent-400': '#c6ff00',
            'accent-700': '#aeea00',
          },
          amber: {
            50: '#fff8e1',
            100: '#ffecb3',
            200: '#ffe082',
            300: '#ffd54f',
            400: '#ffca28',
            500: '#ffc107',
            600: '#ffb300',
            700: '#ffa000',
            800: '#ff8f00',
            900: '#ff6f00',
            'accent-100': '#ffe57f',
            'accent-200': '#ffd740',
            'accent-400': '#ffc400',
            'accent-700': '#ffab00',
          },
          yellow: {
            50: '#fffde7',
            100: '#fff9c4',
            200: '#fff59d',
            300: '#fff176',
            400: '#ffee58',
            500: '#ffeb3b',
            600: '#fdd835',
            700: '#fbc02d',
            800: '#f9a825',
            900: '#f57f17',
            'accent-100': '#ffff8d',
            'accent-200': '#ffff00',
            'accent-400': '#ffea00',
            'accent-700': '#ffd600',
          },
          orange: {
            50: '#fff3e0',
            100: '#ffe0b2',
            200: '#ffcc80',
            300: '#ffb74d',
            400: '#ffa726',
            500: '#ff9800',
            600: '#fb8c00',
            700: '#f57c00',
            800: '#ef6c00',
            900: '#e65100',
            'accent-100': '#ffd180',
            'accent-200': '#ffab40',
            'accent-400': '#ff9100',
            'accent-700': '#ff6d00',
          },
          'deep-orange': {
            50: '#fbe9e7',
            100: '#ffccbc',
            200: '#ffab91',
            300: '#ff8a65',
            400: '#ff7043',
            500: '#ff5722',
            600: '#f4511e',
            700: '#e64a19',
            800: '#d84315',
            900: '#bf360c',
            'accent-100': '#ff9e80',
            'accent-200': '#ff6e40',
            'accent-400': '#ff3d00',
            'accent-700': '#dd2c00',
          },
          brown: {
            50: '#efebe9',
            100: '#d7ccc8',
            200: '#bcaaa4',
            300: '#a1887f',
            400: '#8d6e63',
            500: '#795548',
            600: '#6d4c41',
            700: '#5d4037',
            800: '#4e342e',
            900: '#3e2723',
          },
        },
        spacing: {
          '7': '1.75rem',
          '9': '2.25rem',
          '28': '7rem',
          '80': '20rem',
          '96': '24rem',
        },
        height: {
          '1/2': '50%',
        },
        scale: {
          '30': '.3',
        },
        boxShadow: {
          outline: '0 0 0 3px rgba(101, 31, 255, 0.4)',
        },
      },
    },
    variants: {
      scale: ['responsive', 'hover', 'focus', 'group-hover'],
      textColor: ['responsive', 'hover', 'focus', 'group-hover'],
      opacity: ['responsive', 'hover', 'focus', 'group-hover'],
      backgroundColor: ['responsive', 'hover', 'focus', 'group-hover'],
    },
    plugins: [require('preline/plugin')],
    content: [
      './app/views/**/*.html.erb',
      './app/helpers/**/*.rb',
      './app/assets/stylesheets/**/*.css',
      './app/javascript/**/*.js',
      'node_modules/preline/dist/*.js'
    ]
  }""".strip
  insert_into_file "./tailwind.config.js", "  " + template + "\n"
end

def add_stimulus_controllers
  run "rails generate stimulus flash"
  say %(Stimuls Flash controller generated succesfully!), :green
end

def add_gem(name, *options)
  gem(name, *options) unless gem_exists?(name)
end

def gem_exists?(name)
  IO.read("Gemfile") =~ /^\s*gem ['"]#{name}['"]/
end

unless rails_6_or_newer?
  puts "Please use Rails 6.0 or newer to create a Jumpstart application"
end

# Main setup
add_template_repository_to_source_path
default_to_esbuild
add_gems

after_bundle do
  set_application_name
  add_users
  add_authorization
  add_javascript
  add_toastr_helper
  add_announcements
  add_notifications
  add_multiple_authentication
  add_sidekiq
  add_friendly_id
  add_bootstrap
  add_whenever
  add_sitemap
  add_announcements_css
  add_tailwind_css
  add_preline_ui_css
  add_toastr_css
  rails_command "active_storage:install"

  # Make sure Linux is in the Gemfile.lock for deploying
  run "bundle lock --add-platform x86_64-linux"

  copy_templates

  add_esbuild_script
  add_tailwind_config
  add_stimulus_controllers

  # Commit everything to git
  unless ENV["SKIP_GIT"]
    git :init
    git add: "."
    # git commit will fail if user.email is not configured
    begin
      git commit: %( -m 'Initial commit' )
    rescue StandardError => e
      puts e.message
    end
  end

  say
  say "Jumpstart app successfully created!", :blue
  say
  say "To get started with your new app:", :green
  say "  cd #{original_app_name}"
  say
  say "  # Update config/database.yml with your database credentials"
  say
  say "  rails db:create"
  say "  rails g noticed:model"
  say "  rails db:migrate"
  say "  rails g madmin:install # Generate admin dashboards"
  say "  gem install foreman"
  say "  bin/dev"
end
