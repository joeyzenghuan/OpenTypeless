platform :osx, '13.0'

target 'OpenTypeless' do
  use_frameworks!

  # Azure Cognitive Services Speech SDK
  pod 'MicrosoftCognitiveServicesSpeech-macOS', '~> 1.40'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end
