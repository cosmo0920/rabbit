require 'English'

require "optparse"
require "ostruct"

require "rabbit/rabbit"
require "rabbit/logger"

Thread.abort_on_exception = true

include Rabbit::GetText

class OptionParser
  class Category
    def initialize(str)
      @name = str
    end

    def summarize(*args, &block)
      yield('')
      yield(@name)
    end

    def summarize_as_roff(&block)
      yield(".SH #{::OptionParser.roff_escape(@name)}")
    end
  end

  class Switch
    def summarize_as_roff(&block)
      opt_str = [@short, @long].flatten.join(', ')
      yield('.TP')
      yield(%[.B "#{::OptionParser.roff_escape(opt_str)}"])
      desc.each do |d|
        yield(::OptionParser.roff_escape(d))
      end
    end
  end

  class List
    def summarize_as_roff(&block)
      list.each do |opt|
        if opt.respond_to?(:summarize_as_roff)
          opt.summarize_as_roff(&block)
        end
        # FIXME: and otherwise process separators and banners...
      end
    end
  end

  # TODO: decide whether we show this option in the option summary.
  Officious['roff'] = proc do |parser|
    Switch::NoArgument.new do
      puts parser.roff
      exit
    end
  end

  def roff
    to = []
    visit(:summarize_as_roff) do |l|
      to << l + $/
    end
    to
  end

  def category(str)
    top.append(Category.new(str), nil, nil)
  end

  def self.roff_escape(str)
    str.gsub(/[-\\]/, '\\\\\\&').gsub(/^[.']/, '\\&') # '
    # TODO: taken over from rd2man-lib.rb, necessary to be confirmed
  end
end

module Rabbit
  module Console
    @@locale_dir_option_name = "--locale-dir"

    module_function
    def parse!(args, logger=nil)
      bindtextdomain
      logger ||= Logger::STDERR.new
      options = OpenStruct.new
      options.logger = logger
      options.default_logger = logger

      process_locale_options(args)

      opts = OptionParser.new(banner) do |opts|
        yield(opts, options)
        setup_common_options(opts, options)
      end

      begin
        opts.parse!(args)
      rescue
        logger.fatal($!.message)
      end

      [options, options.logger]
    end

    def banner
      _("Usage: %s [options]") % File.basename($0, '.*')
    end

    def process_locale_options(args)
      args.each_with_index do |arg, i|
        if arg == @@locale_dir_option_name
          bindtextdomain(args[i + 1])
        elsif /#{@@locale_dir_option_name}=/ =~ arg
          bindtextdomain($POSTMATCH)
        end
      end
    end

    def setup_common_options(opts, options)
      opts.separator ""
      opts.separator _("Common options")

      setup_locale_options(opts, options)
      setup_logger_options(opts, options)
      setup_common_options_on_tail(opts, options)
    end
    
    def setup_locale_options(opts, options)
      opts.on("--locale-dir=DIR",
              _("Specify locale dir as [DIR]."),
              _("(auto)")) do |d|
        bindtextdomain(d)
      end

      opts.separator ""
    end

    def setup_logger_options(opts, options)
      logger_type_names = Rabbit::Logger.types.collect do |x|
        get_last_name(x).downcase
      end

      opts.on("--logger-type=TYPE",
              logger_type_names,
              _("Specify logger type as [TYPE]."),
              _("Select from [%s].") % logger_type_names.join(', '),
              _("Note: case insensitive."),
              "(#{get_last_name(options.logger.class)})") do |logger_type|
        logger_class = Rabbit::Logger.types.find do |t|
          get_last_name(t).downcase == logger_type.downcase
        end
        if logger_class.nil?
          options.logger = options.default_logger
          # logger.error("Unknown logger type: #{t}")                           
        else
          options.logger = logger_class.new
        end
      end

      opts.separator ""
    end

    def setup_common_options_on_tail(opts, options)
      opts.on_tail("--help", _("Show this message.")) do
        output_info_and_exit(options, opts.to_s)
      end

      opts.on_tail("--version", _("Show version.")) do
        output_info_and_exit(options, "#{VERSION}\n")
      end
    end

    def output_info_and_exit(options, message)
      if options.logger.is_a?(Logger::STDERR) and
          options.default_logger == options.logger
        print(GLib.locale_from_utf8(message))
      else
        options.logger.info(message)
      end
      exit
    end

    def get_last_name(klass)
      klass.name.split("::").last
    end
  end
end
