Pod::Spec.new do |s|
  s.name          = "ContactsKit"
  s.version       = "0.0.1"
  s.summary       = "Simple Swift wrapper for Contacts framework that works on iOS."
  s.homepage      = "https://github.com/wata/ContactsKit"
  s.license       = { :type => "MIT", :file => "LICENSE" }
  s.author        = "Wataru Nagasawa"
  s.source        = { :git => "#{s.homepage}.git", :tag => s.version.to_s }
  s.platform      = :ios, '11.0'
  s.swift_version = '5.0'
  s.source_files  = "ContactsKit/**/*.swift"
end