Pod::Spec.new do |s|
  s.name             = 'VideoFrameCapture'
  s.version          = '1.0.0'
  s.summary          = 'Native video frame capture for FFI'
  s.description      = 'Captures video frames from WebRTC tracks for use in Flame game engine via FFI'
  s.homepage         = 'https://github.com/enspyrco/tech_world'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Tech World' => 'tech@enspyr.co' }
  s.source           = { :path => '.' }
  s.source_files     = '*.{h,m}'
  s.platform         = :osx, '10.15'
  s.dependency 'WebRTC-SDK'
  s.dependency 'flutter_webrtc'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES'
  }
end
