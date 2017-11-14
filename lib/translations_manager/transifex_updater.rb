require 'open3'
require 'psych'
require 'set'
require 'fileutils'

module TranslationsManager
  class TransifexUpdater

    YML_FILE_COMMENTS = <<END
# encoding: utf-8
#
# Never edit this file. It will be overwritten when translations are pulled from Transifex.
#
# To work with us on translations, join this project:
# https://www.transifex.com/projects/p/discourse-org/
END

    def initialize(yml_dirs, yml_file_prefixes, *languages)

      if `which tx`.strip.empty?
        puts '', 'The Transifex client needs to be installed to use this script.'
        puts 'Instructions are here: http://docs.transifex.com/client/setup/'
        puts '', 'On Mac:', ''
        puts '  sudo easy_install pip'
        puts '  sudo pip install transifex-client', ''
        raise RuntimeError.new("Transifex client needs to be installed")
      end

      @yml_dirs = yml_dirs
      @yml_file_prefixes = yml_file_prefixes

      if languages.empty?
        @languages = Dir.glob(
          File.expand_path(
            File.join('..', '..', yml_dirs.first, "#{yml_file_prefixes.first}.*.yml"),
            __FILE__
          )
        ).map { |x| x.split('.')[-2] }
      else
        @languages = languages
      end

      @languages = @languages.select { |x| x != 'en' }.sort
    end

    def perform
      # ensure that all locale files exists. tx doesn't create missing locale files during pull
      @yml_dirs.each do |dir|
        @yml_file_prefixes.each do |prefix|
          @languages.each do |language|
            filename = yml_path(dir, prefix, language)
            FileUtils.touch(filename) unless File.exists?(filename)
          end
        end
      end

      puts 'Pulling new translations...', ''
      command = "tx pull --mode=developer --language=#{@languages.join(',')} --force"

      Open3.popen2e(command) do |stdin, stdout_err, wait_thr|
        while (line = stdout_err.gets)
          puts line
        end
      end
      puts ''

      unless $?.success?
        puts 'Something failed. Check the output above.', ''
        exit $?.exitstatus
      end

      @yml_dirs.each do |dir|
        @yml_file_prefixes.each do |prefix|
          english_alias_data = get_english_alias_data(dir, prefix)

          @languages.each do |language|
            filename = yml_path_if_exists(dir, prefix, language)

            if filename
              update_file_header(filename, language)
            end
          end
        end
      end
    end

    def yml_path(dir, prefix, language)
      path = "../../#{dir}/#{prefix}.#{language}.yml"
      File.expand_path(path, __FILE__)
    end

    def yml_path_if_exists(dir, prefix, language)
      path = yml_path(dir, prefix, language)
      File.exists?(path) ? path : nil
    end

    # Add comments to the top of files and replace the language (first key in YAML file)
    def update_file_header(filename, language)
      lines = File.readlines(filename)
      lines.collect! { |line| line.gsub!(/^[a-z_]+:( {})?$/i, "#{language}:\\1") || line }

      File.open(filename, 'w+') do |f|
        f.puts(YML_FILE_COMMENTS, '') unless lines[0][0] == '#'
        f.puts(lines)
      end
    end
  end
end