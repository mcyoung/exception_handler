####################
#      Table       #
####################

# Schema
###################
# user_id         track the user that had the issue        
# admin_id        track the admin that had the issue
# class_name      @exception.class.name
# status          ActionDispatch::ExceptionWrapper.new(@request.env, @exception).status_code
# message         @exception.message
# trace           @exception.backtrace.join("\n")
# target          @request.url
# referer         @request.referer
# params          @request.params.inspect
# user_agent      @request.user_agent
# ip_address      @request.ip_address
# created_at
# updated_at

module ExceptionHandler
  class Exception < ActiveRecord::Base
    self.table_name = 'errors'

    BOTS = %w(Baidu Gigabot Googlebot libwww-per lwp-trivial msnbot SiteUptime Slurp Wordpress ZIBB ZyBorg Yandex Jyxobot Huaweisymantecspider ApptusBot).freeze

    ATTRS = %i(class_name status message trace target referer params user_agent browser ip_address email_delivery_cycle).freeze

    BOOL_ATTRS = %i(bot_likely).freeze

    REF_ATTRS = %i(user_id admin_id).freeze
  
    # => Exceptions to be rescued by ExceptionHandler
    EXCEPTIONS_TO_BE_RESCUED = [ActionController::RoutingError, AbstractController::ActionNotFound].tap do |list|
      list << ActiveRecord::RecordNotFound if defined?(ActiveRecord)
      list << Mongoid::Errors::DocumentNotFound if defined?(Mongoid)
    end

    after_initialize :set_attributes, unless: ->{ self.persisted? }

    def set_attributes
      (REF_ATTRS + BOOL_ATTRS + ATTRS).each {|type| self[type] = self.public_send("set_#{type.to_s}") }
    end

    

    ####################
    #     Options      #
    ####################

    # => Email
    # => after_initialize invoked after .new method called
    # => Should have been after_create but user may not save
    after_initialize :send_email, unless: ->{ self.persisted? }

    def send_email
      if ExceptionHandler.config.try(:email).try(:[], :to).try(:is_a?, String) && ExceptionHandler.config.try(:email).try(:[], :from).try(:is_a?, String)  
        if ExceptionHandler.config.try(:email).try(:[], :never_codes).try(:exclude?, self.set_status) && ExceptionHandler.config.try(:email).try(:[], :hourly_digest_codes).try(:exclude?, self.set_status) && ExceptionHandler.config.try(:email).try(:[], :daily_digest_codes).try(:exclude?, self.set_status)
          # Configuration did not say to exclude emailing this code, and the code isn't delayed to a summary email:
          ExceptionHandler::ExceptionMailer.new_exception(self).deliver

          self.was_emailed = true
        end
      end
    end



    # => Attributes
    attr_accessor :request, :klass, :exception, :description

    # => Validations
    validates :klass, exclusion:    { in: EXCEPTIONS_TO_BE_RESCUED, message: "%{value}" }, if: -> { set_referer.blank? } # => might need full Proc syntax
    validates :user_agent, format:  { without: Regexp.new( BOTS.join("|"), Regexp::IGNORECASE ) }

    ####################################
    # Virtual
    ####################################

    # => Klass
    # => Used for validation (needs to be cleaned up in 0.7.0)
    def klass
      exception.class
    end

    # => Exception (virtual)
    def exception
      request.env['action_dispatch.exception']
    end

    # => Description
    def description
      I18n.with_options scope: [:exception_handler], message: message, status: set_status do |i18n|
        i18n.t response, default: Rack::Utils::HTTP_STATUS_CODES[set_status] || set_status
      end
    end

    ####################################
    # Exception
    ####################################

    # => Class Name
    def set_class_name
      exception.class.name
    end

    # => Message
    def set_message
      exception.message
    end

    # => Trace
    def set_trace
      exception.backtrace.join("\n")
    end

    ####################################
    # Request
    ####################################

    # => Target URL
    def set_target
      request.url
    end

    # => Referrer URL
    def set_referer
      request.referer
    end

    # => Params
    def set_params
      request.filtered_parameters.inspect
    end

    # => User Agent
    def set_user_agent
      request.user_agent
    end

    def set_browser
      begin
        Browser.new(request.user_agent).name
      rescue
        '-- Browser Gem Not Available --'
      end
    end

    def set_bot_likely
      begin
        Browser.new(request.user_agent).bot?
      rescue
        false
      end
    end

    def set_ip_address
      request.remote_ip if ExceptionHandler.config.try(:ip_address) && ExceptionHandler.config.ip_address[:track]
    end

    def current_user
      request.controller_instance.try(ExceptionHandler.config.try(:current_user_method).to_s)
    end

    def set_user_id
      current_user.try(:id)
    end

    def current_admin
      request.controller_instance.try(ExceptionHandler.config.try(:current_admin_method).to_s)
    end

    def set_admin_id
      current_admin.try(:id)
    end

    def set_email_delivery_cycle
      if ExceptionHandler.config.try(:email).try(:[], :hourly_digest_codes).try(:include?, set_status)
        'hourly'
      elsif ExceptionHandler.config.try(:email).try(:[], :daily_digest_codes).try(:include?, set_status)
        'daily'
      elsif ExceptionHandler.config.try(:email).try(:[], :never_codes).try(:include?, set_status)
        'never'
      else
        'instant'
      end
    end

    ####################################
    # Other
    ####################################

    # => Status code (404, 500 etc)
    def set_status
      ActionDispatch::ExceptionWrapper.new(request.env, exception).status_code
    end

    # => Server Response ("Not Found" etc)
    def response
      ActionDispatch::ExceptionWrapper.rescue_responses[class_name]
    end

    ##################################
    ##################################

    scope :hourly, ->{ where(email_delivery_cycle: 'hourly') }
    scope :daily,  ->{ where(email_delivery_cycle: 'daily') }
    scope :not_sent, -> { where(was_emailed: false) }

    def self.collect_and_send(cycle = 'hourly')
      error_list = self.not_sent

      error_list = case cycle
      when 'hourly' then error_list.hourly
      when 'daily' then error_list.daily
      end

      return if error_list.length.zero?

      errors_to_alert = error_list.group_by{|e| [e[:status], e[:ip_address], e[:class_name]] }

      ExceptionHandler::ExceptionMailer.collection_email(cycle, errors_to_alert).deliver

      error_list.update_all(was_emailed: true)
    end # self.collect_and_send
  end
end

