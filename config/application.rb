if defined?(Rake.application) && Rake.application.top_level_tasks.grep(/jenkins/).any?
  ENV['RAILS_ENV'] ||= 'test'
end
require File.expand_path('boot', __dir__)
require 'apipie/middleware/checksum_in_headers'

# Only import the frameworks we need - this list is taken from rails/all
require "rails"

[
  'active_record/railtie',
  # 'active_storage/engine',
  'action_controller/railtie',
  'action_view/railtie',
  'action_mailer/railtie',
  'active_job/railtie',
  # 'action_cable/engine',
  # 'action_mailbox/engine',
  # 'action_text/engine',
  'rails/test_unit/railtie',
  'sprockets/railtie',
].each do |railtie|
  require railtie
end

require File.expand_path('../config/settings', __dir__)

if File.exist?(File.expand_path('../Gemfile.in', __dir__))
  # If there is a Gemfile.in file, we will not use Bundler but BundlerExt
  # gem which parses this file and loads all dependencies from the system
  # rathern then trying to download them from rubygems.org. It always
  # loads all gemfile groups.
  require 'bundler_ext'
  Bundler.ui = Bundler::UI::Silent.new if Rails.env.production?
  BundlerExt.system_require(File.expand_path('../Gemfile.in', __dir__), :all)

  class Foreman::Consoletie < Rails::Railtie
    console { Foreman.setup_console }
  end
else
  # If you have a Gemfile, require the gems listed there
  # Note that :default, :test, :development and :production groups
  # will be included by default (and dependending on the current environment)
  if defined?(Bundler)
    Bundler.ui = Bundler::UI::Silent.new if Rails.env.production?

    class Foreman::Consoletie < Rails::Railtie
      console do
        begin
          Bundler.require(:console)
        rescue LoadError
          # no action, logs a warning in setup_console only
        end
        Foreman.setup_console
      end
    end
    Bundler.require(*Rails.groups)
    optional_bundler_groups = %w[assets ec2 fog libvirt openstack ovirt vmware redis]
    optional_bundler_groups.each do |group|
      Bundler.require(group)
    rescue LoadError
      # ignoring intentionally
    end
  end
end

# Content of these files is being used before Zeitwerk does auto/eager loading
# We need to call either require with the full path or require_relative with relative path since /lib is not in $LOAD_PATH yet here
# $LOAD_PATH is available in config/initializers though
require_relative '../lib/foreman'
require_relative '../lib/foreman/dynflow'

if SETTINGS[:support_jsonp]
  if File.exist?(File.expand_path('../Gemfile.in', __dir__))
    BundlerExt.system_require(File.expand_path('../Gemfile.in', __dir__), :jsonp)
  else
    Bundler.require(:jsonp)
  end
end

module Foreman
  class Application < Rails::Application
    config.load_defaults '7.0'

    # Rails 5.0 changed this to true, but a lot of code depends on this
    config.active_record.belongs_to_required_by_default = false

    # Rails 5.1 changed this to false, re-enabling this due to https://github.com/theforeman/foreman/pull/9711/files#r1247901552
    config.assets.unknown_asset_fallback = true

    # Rails 5.2 changed this to true, but we already do this in app/controllers/application_controller.rb#7
    # We don't use this default because it's applied to ActionController::Base, thus to all inherited controllers
    # But for API controllers we use a modification: app/controllers/concerns/foreman/controller/api_csrf_protection.rb#7
    config.action_controller.default_protect_from_forgery = false
    # Rails 5.2 changed this to true, but the only thing it does currently (as of Rails 7.0) is
    # changing default cipher from aes-256-cbc to aes-256-gcm.
    # Leaving this disabled, since the application worked with aes-256-cbc.
    # Failed tests on aes-256-gcm require revisit application to ensure we can do the switch.
    config.active_support.use_authenticated_message_encryption = false
    config.action_dispatch.use_authenticated_cookie_encryption = false

    # Rails 6.1 changed this to true, but apparently our codebase is not ready for bidirectional associations
    config.active_record.has_many_inversing = false

    # Rails 7.0 changed this to true
    config.active_record.verify_foreign_keys_for_fixtures = false
    config.active_record.automatic_scope_inversing = false

    # Setup additional routes by loading all routes file from routes directory
    Dir["#{Rails.root}/config/routes/**/*.rb"].each do |route_file|
      config.paths['config/routes.rb'] << route_file
    end

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Recommended by Rails: https://guides.rubyonrails.org/v7.0/configuring.html#config-add-autoload-paths-to-load-path
    config.add_autoload_paths_to_load_path = false
    # Autoloading
    config.autoload_paths += %W(#{config.root}/app/models/auth_sources)
    config.autoload_paths += %W(#{config.root}/app/models/compute_resources)
    config.autoload_paths += %W(#{config.root}/app/models/fact_names)
    config.autoload_paths += %W(#{config.root}/app/models/lookup_keys)
    config.autoload_paths += %W(#{config.root}/app/models/operatingsystems)
    config.autoload_paths += %W(#{config.root}/app/models/parameters)
    config.autoload_paths += %W(#{config.root}/app/models/taxonomies)
    config.autoload_paths += %W(#{config.root}/app/models/mail_notifications)

    # Custom directories that will only be loaded once
    # Should only contain classes with class-level data set by initializers (registries etc.)
    config.autoload_once_paths += %W(#{config.root}/app/registries)

    # Eager load all classes under lib directory
    config.eager_load_paths += ["#{config.root}/lib"]
    config.eager_load_paths += ["#{config.root}/app/lib"]

    # Only load the plugins named here, in the order given (default is alphabetical).
    # :all can be used as a placeholder for all plugins not explicitly named.
    # config.plugins = [ :exception_notification, :ssl_requirement, :all ]

    config.force_ssl = SETTINGS[:require_ssl]
    config.ssl_options = {
      redirect: {
        exclude: ->(request) { Foreman::ForceSsl.new(request).allows_http? },
      },
    }

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'
    config.time_zone = 'UTC'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    # Don't enforce known locales with exceptions, as fast_gettext has a fallback to default 'en'
    config.i18n.enforce_available_locales = false

    # Disable fieldWithErrors divs
    config.action_view.field_error_proc = proc { |html_tag, instance| html_tag.to_s.html_safe }

    # Configure the default encoding used in templates for Ruby 1.9.
    config.encoding = "utf-8"

    # Configure sensitive parameters which will be filtered from the log file.
    config.filter_parameters += [:password, :account_password, :facts, :root_pass, :value, :report, :password_confirmation, :secret]

    # Enable escaping HTML in JSON.
    config.active_support.escape_html_entities_in_json = true

    # Don't raise exception for common parameters
    config.action_controller.always_permitted_parameters = %w(
      controller action format locale utf8 _method authenticity_token commit redirect
      page per_page paginate search order sort sort_by sort_order
      _ _ie_support fakepassword apiv id organization_id location_id user_id
    )

    # Use SQL instead of Active Record's schema dumper when creating the database.
    # This is necessary if your schema can't be completely dumped by the schema dumper,
    # like if you have constraints or database-specific column types
    config.active_record.schema_format = :sql

    # Starting 6.1.6.1 Rails forced users to explicitly list all the classes
    # that are allowed to be loaded by Psych
    # (https://github.com/rails/rails/pull/45584#issuecomment-1183255990)
    config.active_record.yaml_column_permitted_classes = [
      Symbol,
      Time,
      ActiveSupport::HashWithIndifferentAccess,
      ActiveSupport::TimeZone,
      ActiveSupport::TimeWithZone,
    ]

    # enables JSONP support in the Rack middleware
    config.middleware.use Rack::JSONP if SETTINGS[:support_jsonp]

    # Enable Rack OpenID middleware
    begin
      require 'rack/openid'
      require 'openid/store/filesystem'
      openid_store_path = Pathname.new(Rails.root).join('db').join('openid-store')
      config.middleware.use Rack::OpenID, OpenID::Store::Filesystem.new(openid_store_path)
    rescue LoadError
      nil
    end

    begin
      if SETTINGS[:telemetry].try(:fetch, :prometheus).try(:fetch, :enabled)
        require 'prometheus/middleware/exporter'
        config.middleware.use Prometheus::Middleware::Exporter
      end
    rescue LoadError, KeyError
      # not configured or bundler group 'telemetry' was disabled
    end

    # Enable the asset pipeline
    config.assets.enabled = true

    # Version of your assets, change this if you want to expire all your assets
    config.assets.version = '1.0'

    # Disable noisy logging of requests for assets
    config.assets.quiet = true

    # When operating behind a reverse proxy, this provides a valid remote ip in request.remote_ip
    # the middleware is enabled by default however we minimize the trusted proxies list
    #
    # the trusted proxies are removed from remote IP candidates, since we know they are proxies and not clients
    # in the default deployment, this is typically an Apache
    #
    # currently the requests with untrusted IPs in X_FORWARDED_FOR are taken into the consideration,
    # the spoof detection based on HTTP_CLIENT_IP header performed by the middleware does not work
    config.action_dispatch.trusted_proxies = SETTINGS.fetch(:trusted_proxies, %w(127.0.0.1/8 ::1)).map { |proxy| IPAddr.new(proxy) }

    # Record request and session tokens in logging MDC
    config.middleware.insert_before Rails::Rack::Logger, Foreman::Middleware::LoggingContextRequest
    config.middleware.insert_after ActionDispatch::Session::ActiveRecordStore, Foreman::Middleware::LoggingContextSession

    # Add apidoc hash in headers for smarter caching
    config.middleware.use Apipie::Middleware::ChecksumInHeaders

    # Add telemetry and connection cleaner
    config.middleware.use Foreman::Middleware::Telemetry
    config.middleware.use Foreman::Middleware::LibvirtConnectionCleaner

    # New config option to opt out of params "deep munging" that was used to address security vulnerability CVE-2013-0155.
    config.action_dispatch.perform_deep_munge = false

    # Use Dynflow as the backend for ActiveJob
    config.active_job.queue_adapter = :dynflow

    config.action_dispatch.return_only_media_type_on_content_type = false

    Foreman::Logging.configure(
      :log_directory => "#{Rails.root}/log",
      :environment => Rails.env,
      :config_overrides => SETTINGS[:logging]
    )

    # Check that the loggers setting exist to configure the app and sql loggers
    Foreman::Logging.add_loggers((SETTINGS[:loggers] || {}).reverse_merge(
      :app => {:enabled => true},
      :audit => {:enabled => true},
      :ldap => {:enabled => false},
      :permissions => {:enabled => false},
      :proxy => {:enabled => false},
      :sql => {:enabled => false},
      :templates => {:enabled => true},
      :notifications => {:enabled => true},
      :background => {:enabled => true},
      :dynflow => {:enabled => true},
      :telemetry => {:enabled => false},
      :blob => {:enabled => false},
      :taxonomy => {:enabled => true},
      :api_deprecations => {:enabled => true},
      :sidekiq => {:enabled => true, :level => :warn}
    ))

    config.logger = Foreman::Logging.logger('app')
    # Explicitly set the log_level from our config, overriding the Rails env default
    config.log_level = Foreman::Logging.logger_level('app').to_sym
    config.active_record.logger = Foreman::Logging.logger('sql')

    # enables in memory cache store with ttl
    rails_cache_settings = SETTINGS[:rails_cache_store]
    if (rails_cache_settings && rails_cache_settings[:type] == 'redis')
      options = [:redis_cache_store]
      redis_urls = Array.wrap(rails_cache_settings[:urls])

      options << {
        namespace: 'foreman',
        url: redis_urls,
        reconnect_attempts: ::Redis::Client::DEFAULTS[:reconnect_attempts],
      }.merge(rails_cache_settings[:options] || {})

      config.cache_store = options
      Foreman::Logging.logger('app').info "Rails cache backend: Redis"
    else
      config.cache_store = :file_store, Rails.root.join('tmp', 'cache/')
      Foreman::Logging.logger('app').info "Rails cache backend: File"
    end

    if config.public_file_server.enabled
      ::Rails::Engine.subclasses.map(&:instance).each do |engine|
        if File.exist?("#{engine.root}/public/assets") || File.exist?("#{engine.root}/public/webpack")
          config.middleware.use ::ActionDispatch::Static, "#{engine.root}/public"
        end
      end
    end

    if Array(SETTINGS[:cors_domains]).present?
      config.middleware.insert_before 0, Rack::Cors do
        allow do
          origins Array(SETTINGS[:cors_domains])
          resource '*', headers: :any, methods: [:get, :post, :options]
        end
      end
    end

    config.to_prepare do
      # AuditExtensions contain code from app/ so can only be loaded after initializing is done
      # otherwise rails auto-reloader won't be able to reload Taxonomies which are linked there
      Audit.include AuditExtensions

      ApplicationController.descendants.each do |child|
        # reinclude the helper module in case some plugin extended some in the to_prepare phase,
        # after the module was already included into controllers
        helpers = child._helpers.ancestors.find_all do |ancestor|
          ancestor.name =~ /Helper$/
        end
        child.helper helpers
      end
    end

    # Use the database for sessions instead of the cookie-based default
    config.session_store :active_record_store, :secure => !!SETTINGS[:require_ssl]

    # We need to mount the sprockets engine before we use the routes_reloader
    initializer(:mount_sprocket_env, :before => :sooner_routes_load) do
      if config.assets.compile
        app = Rails.application
        if Sprockets::Railtie.instance.respond_to?(:build_environment)
          app.assets = Sprockets::Railtie.instance.build_environment(app, true)
        end
        routes.prepend do
          mount app.assets => app.config.assets.prefix
        end
      end
    end

    # We use the routes_reloader before the to_prepare and eager_load callbacks
    # to make the routes load sooner than the controllers. Otherwise, the definition
    # of named routes helpers in the module significantly slows down the startup
    # of the application. Switching the order helps a lot.
    initializer(:sooner_routes_load, :before => :run_prepare_callbacks) do
      routes_reloader.execute_if_updated
    end

    initializer(:register_gettext, :after => :load_config_initializers) do |app|
      ::Foreman::Plugin.all.select { |p| p.gettext_domain }.each do |plugin|
        Foreman::Gettext::Support.add_text_domain plugin.gettext_domain, plugin.locale_path
      end
    end

    config.after_initialize do
      require 'fog_extensions'

      init_dynflow unless Foreman.in_rake?('db:create') || Foreman.in_rake?('db:drop')
      setup_auditing
    end

    def dynflow
      return @dynflow if @dynflow.present?
      @dynflow =
        if defined?(ForemanTasks)
          ForemanTasks.dynflow
        else
          ::Dynflow::Rails.new(nil, ::Foreman::Dynflow::Configuration.new)
        end
      @dynflow.require!
      @dynflow
    end

    def init_dynflow
      dynflow.eager_load_actions!
    end

    def setup_auditing
      Audit.include AuditSearch
      Audit.include HasManyCommon
    end
  end

  def self.setup_console
    ENV['IRBRC'] = File.expand_path('irbrc', __dir__)
    User.current = User.anonymous_console_admin
    Rails.logger.warn "Console started with '#{User.current.login}' user, call User.current= to change it"
  end
end
