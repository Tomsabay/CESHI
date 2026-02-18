Pod::Spec.new do |s|
  s.name             = 'WeReadIntegration'
  s.version          = '1.0.0'
  s.summary          = '微信读书与 Claude iOS App 集成模块'
  s.description      = <<-DESC
    让 Claude iOS App 能够读取用户微信读书账号中的书架、划线、笔记和阅读统计数据，
    并通过 Claude API 进行 AI 分析，包括阅读报告生成、书单推荐、笔记整理等功能。
  DESC

  s.homepage         = 'https://github.com/anthropics/claude-code'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Anthropic' => 'dev@anthropic.com' }
  s.source           = { :git => '.', :tag => s.version.to_s }

  s.ios.deployment_target = '16.0'
  s.swift_version = '5.9'

  s.source_files = 'WeReadIntegration/**/*.swift'

  s.frameworks = 'SwiftUI', 'WebKit', 'Security', 'AuthenticationServices'
end
