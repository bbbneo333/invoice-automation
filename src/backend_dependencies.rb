bundled_zip = File.join(__dir__, "..", "vendor", "rubyzip", "lib")
if File.directory?(bundled_zip)
  $LOAD_PATH.unshift(bundled_zip)
else
  ENV["BUNDLE_GEMFILE"] = File.expand_path("../Gemfile", __dir__)
  require "bundler/setup"
end

require "zip"
require "zip/version"
raise "Expected bundled rubyzip 2.4.1, got #{Zip::VERSION}" unless Zip::VERSION == "2.4.1"
