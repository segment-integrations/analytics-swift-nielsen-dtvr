//
//  SEGNielsenVideoPlayerViewController.swift
//  BasicExample
//
//  Created by Komal Dhingra on 01/02/23.
//

import SwiftUI
import Segment
import UIKit
import SegmentNielsenDTVR
import AVKit

/*
 This sample custom video player demonstrates firing several analytics events to Segment which have a mapping with the Nielsen SDK.
 The following events are tracked:
 - Video Content Started
 - Video Content Completed
 - Video Playback Paused
 - Video Playback Resumed
 - Video Playback Completed
 - Video Playback Seek Started
 - Video Playback Seek Completed
 - Video Playback Buffer Started
 - Video Playback Buffer Completed
 - Video Playback Interrupted *
 - Application Backgrounded
 
 *
 For this event, only the application backgrounding scenario was accounted for. Per Segment requirements, other conditions should trigger this event. See https://segment.com/docs/spec/video/ for more information.
 */
struct SEGNielsenVideoPlayerView: View {
    
    var model: SEGVideoModel!
    var isPlaying: Bool!
    var player: AVPlayer!
    
    // The progress through the video, as a percentage (from 0 to 1)
    @State private var videoPos: Double = 0
    // The duration of the video in seconds
    @State private var videoDuration: Double = 0
    // Whether we're currently interacting with the seek bar or doing a seek
    @State private var seeking = false
    
    @Environment(\.dismiss) var dismiss
    
    init(videoModel: SEGVideoModel) {
        player = AVPlayer(url: URL(string: videoModel.url)!)
        model = videoModel
    }
    
    var body: some View {
        VStack {
            ZStack(alignment: .topLeading) {
                HStack {
                    Button(action: {
                        print("close button pressed")
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle")
                            .renderingMode(.original)
                    }.padding(30)
                    Spacer()
                }
            }
            Spacer()
            VideoPlayerView(videoPos: $videoPos,
                            videoDuration: $videoDuration,
                            seeking: $seeking, videoPlayerProperties: trackingPropertiesForModelWithCurrentPlayProgress(),
                            player: player)
            VideoPlayerControlsView(videoPos: $videoPos,
                                    videoDuration: $videoDuration,
                                    seeking: $seeking, player: player, videoPlayerProperties: trackingPropertiesForModelWithCurrentPlayProgress())
            
        }
        .onAppear(){
            if player.currentItem == nil {
                let item = AVPlayerItem(url: URL(string: model.url)!)
                player.replaceCurrentItem(with: item)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                player.play()
            })
            addNotificationListners()
            
        }
        .onDisappear {
            // When this View isn't being shown anymore stop the player
            self.player.replaceCurrentItem(with: nil)
        }
    }
}

// This is the UIView that contains the AVPlayerLayer for rendering the video
class VideoPlayerUIView: UIView {
    private let player: AVPlayer
    private let playerLayer = AVPlayerLayer()
    private let videoPos: Binding<Double>
    private let videoDuration: Binding<Double>
    private let seeking: Binding<Bool>
    private var durationObservation: NSKeyValueObservation?
    private var timeObservation: Any?
    private var statusObserver: NSKeyValueObservation?
    private var videoPlayerProperties: [String: Any]
    
    init(player: AVPlayer, videoPos: Binding<Double>, videoDuration: Binding<Double>, seeking: Binding<Bool>, videoPlayerProperties: [String: Any]) {
        self.player = player
        self.videoDuration = videoDuration
        self.videoPos = videoPos
        self.seeking = seeking
        self.videoPlayerProperties = videoPlayerProperties
        super.init(frame: .zero)
        
        backgroundColor = .white
        playerLayer.player = player
        layer.addSublayer(playerLayer)
        
        
        statusObserver = player.currentItem?.observe(\.status, options:  [.new, .old], changeHandler: { (playerItem, change) in
            if playerItem.status == .readyToPlay {
                Analytics.main.log(message: "LOG: tracking Video Content Started")
                Analytics.main.track(name: "Video Content Started", properties: videoPlayerProperties)
            }
        })
        
        // Observe the duration of the player's item so we can display it
        // and use it for updating the seek bar's position
        durationObservation = player.currentItem?.observe(\.duration, changeHandler: { [weak self] item, change in
            guard let self = self else { return }
            self.videoDuration.wrappedValue = item.duration.seconds
        })
        
        // Observe the player's time periodically so we can update the seek bar's
        // position as we progress through playback
        timeObservation = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: nil) { [weak self] time in
            guard let self = self else { return }
            // If we're not seeking currently (don't want to override the slider
            // position if the user is interacting)
            guard !self.seeking.wrappedValue else {
                return
            }
            // update videoPos with the new video time (as a percentage)
            self.videoPos.wrappedValue = time.seconds / self.videoDuration.wrappedValue
            if player.currentItem?.isPlaybackLikelyToKeepUp == true {
                self.handleBufferWithPlaybackLikelyToKeepUp(isPlaybackLikelyToKeepUp: true, isPlaybackBufferEmpty: false)
            }
            if player.currentItem?.isPlaybackBufferEmpty == true {
                self.handleBufferWithPlaybackLikelyToKeepUp(isPlaybackLikelyToKeepUp: false, isPlaybackBufferEmpty: true)
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        playerLayer.frame = bounds
    }
    
    func cleanUp() {
        // Remove observers we setup in init
        durationObservation?.invalidate()
        durationObservation = nil
        
        statusObserver?.invalidate()
        statusObserver = nil
        
        if let observation = timeObservation {
            player.removeTimeObserver(observation)
            timeObservation = nil
        }
    }
    
    func handleBufferWithPlaybackLikelyToKeepUp(isPlaybackLikelyToKeepUp: Bool, isPlaybackBufferEmpty: Bool) {
        if !isPlaybackLikelyToKeepUp && isPlaybackBufferEmpty {
            Analytics.main.log(message: "tracking Video Playback Buffer Started")
            Analytics.main.track(name: "Video Playback Buffer Started", properties: videoPlayerProperties)
        }
        else if isPlaybackLikelyToKeepUp && !isPlaybackBufferEmpty {
            Analytics.main.log(message: "tracking Video Playback Buffer Completed")
            Analytics.main.track(name: "Video Playback Buffer Completed", properties: videoPlayerProperties)
        }
    }
}

// This is the SwiftUI view which wraps the UIKit-based PlayerUIView above
struct VideoPlayerView: UIViewRepresentable {
    @Binding private(set) var videoPos: Double
    @Binding private(set) var videoDuration: Double
    @Binding private(set) var seeking: Bool
    var videoPlayerProperties: [String: Any]
    
    let player: AVPlayer
    
    func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<VideoPlayerView>) {
        // This function gets called if the bindings change, which could be useful if
        // you need to respond to external changes, but we don't in this example
        
    }
    
    func makeUIView(context: UIViewRepresentableContext<VideoPlayerView>) -> UIView {
        let uiView = VideoPlayerUIView(player: player,
                                       videoPos: $videoPos,
                                       videoDuration: $videoDuration,
                                       seeking: $seeking, videoPlayerProperties: videoPlayerProperties)
        return uiView
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        guard let playerUIView = uiView as? VideoPlayerUIView else {
            return
        }
        
        playerUIView.cleanUp()
    }
}

// This is the SwiftUI view that contains the controls for the player
struct VideoPlayerControlsView : View {
    @Binding private(set) var videoPos: Double
    @Binding private(set) var videoDuration: Double
    @Binding private(set) var seeking: Bool
    
    let player: AVPlayer
    @State private var playerPaused = true
    @State var videoPlayerProperties = [String: Any]()
    
    var body: some View {
        HStack {
            // Play/pause button
            Button(action: togglePlayPause) {
                Image(systemName: playerPaused ? "play" : "pause")
                    .padding(.trailing, 10)
            }
            // Current video time
            Text("\(Utility.formatSecondsToHMS(videoPos * videoDuration))")
            // Slider for seeking / showing video progress
            Slider(value: $videoPos, in: 0...1, onEditingChanged: sliderEditingChanged)
            // Video duration
            Text("\(Utility.formatSecondsToHMS(videoDuration))")
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
    }
    
    private func togglePlayPause() {
        pausePlayer(!playerPaused)
    }
    
    private func pausePlayer(_ pause: Bool) {
        playerPaused = pause
        if !playerPaused {
            pauseAndTrack(trackEvent: true)
        }
        else {
            Analytics.main.log(message: "LOG: tracking Video Playback Resumed")
            Analytics.main.track(name: "Video Playback Resumed", properties: videoPlayerProperties)
            player.play()
        }
    }
    
    private func pauseAndTrack(trackEvent: Bool) {
        player.pause()
        if trackEvent {
            Analytics.main.log(message: "LOG: tracking Video Playback Paused")
            Analytics.main.track(name: "Video Playback Paused", properties: videoPlayerProperties)
        }
    }
    
    private func sliderEditingChanged(editingStarted: Bool) {
        if editingStarted {
            // Set a flag stating that we're seeking so the slider doesn't
            // get updated by the periodic time observer on the player
            videoPlayerProperties["seek_position"] = "\(Utility.formatSecondsToHMS(videoPos * videoDuration))"
            Analytics.main.log(message: "LOG: tracking Video Playback Seek Started")
            Analytics.main.track(name: "Video Playback Seek Started", properties: videoPlayerProperties)
            seeking = true
            pausePlayer(true)
        }
        
        // Do the seek if we're finished
        if !editingStarted {
            let targetTime = CMTime(seconds: videoPos * videoDuration,
                                    preferredTimescale: 600)
            player.seek(to: targetTime) { _ in
                // Now the seek is finished, resume normal operation
                Analytics.main.log(message: "LOG: tracking Video Playback Seek Completed")
                Analytics.main.track(name: "Video Playback Seek Completed", properties: videoPlayerProperties)
                self.seeking = false
                self.pausePlayer(false)
            }
        }
    }
}

struct SEGNielsenVideoPlayerView_Previews: PreviewProvider {
    
    static var previews: some View {
        SEGNielsenVideoPlayerView(videoModel: SEGVideoModel(videoId: "1234", url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4", loadType: "linear", channelName: "defaultChannel"))
    }
    
    
}
extension SEGNielsenVideoPlayerView {
    
    //MARK:- Notification listners
    func addNotificationListners(){
        NotificationCenter.default.addObserver(forName: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil, queue: nil, using: self.handlePlaybackEndedNotification(_:))
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil, using: self.handlePlaybackEndedNotification(_:))
    }
    
    func handlePlaybackEndedNotification(_ notification: Notification) {
        Analytics.main.log(message: "LOG: tracking Video Content Completed")
        Analytics.main.track(name: "Video Content Completed", properties: trackingPropertiesForModelWithCurrentPlayProgress())
        
        DispatchQueue.main.async {
            closePlayer()
        }
    }
    
    mutating func handleAppBackgroundedNotification(_ notification: Notification) {
        if isPlaying {
            // Default behaviour is to pause on background, no auto-resume in this sample
            isPlaying = false
            Analytics.main.log(message: "LOG: tracking Video Playback Interrupted")
            Analytics.main.track(name: "Video Playback Interrupted", properties: trackingPropertiesForModelWithCurrentPlayProgress())
        }
        Analytics.main.log(message: "LOG: tracking Application Backgrounded")
        Analytics.main.track(name: "Application Backgrounded")
    }
    
    //Close player with dismiss view
    func closePlayer() {
        player.pause()
        Analytics.main.track(name: "Video Playback Completed")
        dismiss()
    }
    
    //Get properties to send
    
    func trackingPropertiesForModelWithCurrentPlayProgress()->[String: Any] {
        var trackingData = [String: Any]()
        if model != nil {
            trackingData = [
                "asset_id" : model.videoId ?? "",
                "channel": model.channelName ?? "",
                "load_type": model.loadType ?? "",
            ]
        }
        return trackingData
    }
    
    func getCurrentPlayerTimeSeconds()-> Int {
        if player != nil {
            let currentTime = player.currentTime()
            let currentTimeSeconds = Int(currentTime.value) / Int(currentTime.timescale)
            return currentTimeSeconds
        }
        return 0
    }
}
