Pod::Spec.new do |spec|
  spec.name         = 'MyMailRuSDK'
  spec.version      = '1.3.0'
  spec.license      = { :type => 'MIT', :file => 'LICENSE' }
  spec.homepage     = 'https://github.com/xyzslash/mymailru-ios-sdk'
  spec.authors      = { 'Anton Grachev' => 'agrachev.86@gmail.com' }
  spec.summary      = 'iOS framework for working with my.mail.ru (мой мир@mail.ru) REST API.'
  spec.source       = { 
    :git => 'https://github.com/xyzslash/mymailru-ios-sdk.git', 
    :tag => '1.3.0' 
  }
  spec.source_files = 'MyMailRuSDK/MyMailRuSDK/*.{h,m}'

  spec.frameworks   =  'CommonCrypto'

  spec.requires_arc = true
end