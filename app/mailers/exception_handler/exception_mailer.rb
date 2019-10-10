module ExceptionHandler
  class ExceptionMailer < ActionMailer::Base

      # Defaults
      default from: 			    ExceptionHandler.config.email[:from]
      default template_path: 	"exception_handler/mailers" # => http://stackoverflow.com/a/18579046/1143732

      def new_exception e
      	@exception = e
        mail to:      ExceptionHandler.config.email[:to],
             subject: "ERROR - #{Rails.application.class.parent_name} - (#{@exception.status}) #{@exception.message}"
        Rails.logger.info "Exception Sent To → #{ExceptionHandler.config.email[:to]}"
      end

      def collection_email(frequency, grouped_exceptions = [])
        @frequency          = frequency.to_s.titleize
        @grouped_exceptions = grouped_exceptions
        
        mail to:      ExceptionHandler.config.email[:to],
             subject: "#{@frequency} Error Digest - #{Rails.application.class.parent_name}"
        Rails.logger.info "#{@frequency} Digest Sent To → #{ExceptionHandler.config.email[:to]}"
      end
  end
end
