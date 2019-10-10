class CreateErrors < ActiveRecord::Migration[5.0]

  # => ATTRS
  require_relative "../../app/models/exception_handler/exception.rb"

  #########################################
  #########################################

    # => Defs
    @@table = ExceptionHandler.config.try(:db)

  #########################################

    # Up
    def up
      create_table @@table do |t|
        ExceptionHandler::REF_ATTRS.each do |attr|
          t.integer attr
        end

        ExceptionHandler::ATTRS.each do |attr|
          t.text attr
        end

        t.boolean :was_emailed, default: false
        t.string :email_delivery_cycle, default: 'instant'

        t.timestamps
      end
    end

  #########################################

    # Down
    def down
      drop_table @@table, if_exists: true
    end

  #########################################
  #########################################

end
