//
//  NielsenDTVRDestination.swift
//  NielsenDTVRDestination
//
//  Created by Komal Dhingra on 1/30/23.
// MIT License
//
// Copyright (c) 2021 Segment
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import Segment
import NielsenAppApi

@objc(SEGNielsenDTVRDestination)
public class ObjCSegmentNielsenDTVR: NSObject, ObjCPlugin, ObjCPluginShim {
    public func instance() -> EventPlugin { return NielsenDTVRDestination() }
}

public class NielsenDTVRDestination: DestinationPlugin {
    public let timeline = Timeline()
    public let type = PluginType.destination
    
    public let key = "Nielsen DTVR"
    public var analytics: Analytics? = nil
    
    private var nielsenDTVRSettings: NielsenDTVRSettings?
    private var nielsenAppApi: NielsenAppApi!
    
    private var eventHandlers = [SEGNielsenEventHandler]()
    private var lastSeenID3Tag: String!
    private var defaultSettings: Settings!
    
    public init() { }
    
    public func update(settings: Settings, type: UpdateType) {
        // Skip if you have a singleton and don't want to keep updating via settings.
        guard type == .initial else { return }
        
        // Grab the settings and assign them for potential later usage.
        // Note: Since integrationSettings is generic, strongly type the variable.
        guard let tempSettings: NielsenDTVRSettings = settings.integrationSettings(forPlugin: self) else { return }
        nielsenDTVRSettings = tempSettings
        
        setupEventHandlers()
        
        var appInformation:[String: String] = [
            "appid": tempSettings.appId,
            "appversion": __destination_version,
            "sfcode": tempSettings.sfcode
        ]
        
        if tempSettings.debug {
            appInformation["nol_devDebug"] = "DEBUG"
        }
        
        
        nielsenAppApi = NielsenAppApi(appInfo: appInformation, delegate: nil)
        
    }
    
    public func track(event: TrackEvent) -> TrackEvent? {
        
        for handler in eventHandlers {
            if handlerEventsContainsTrackEvent(eventString: event.event, eventHandlerArray: handler.events ?? []) {
                handler.eventHandler?(nielsenAppApi, event)
                break
            }
        }
        
        return event
    }
    
    /**
     @return Opt-out URL string from the Nielsen App API to display in a web view.
     */
    
    public func optOutURL()->String {
        return nielsenAppApi.optOutURL
    }
    
    /**
     @param urlString URL string from user's action to denote opt-out status for the Nielsen App API. Should be one of `nielsenappsdk://1` or `nielsenappsdk://0` for opt-out and opt-in, respectively
     @seealso https://engineeringportal.nielsen.com/docs/DTVR_iOS_SDK#The_legacy_opt-out_method_works_as_follows:
     */
    
    public func userOptOutStatus(urlString: String) {
        nielsenAppApi.userOptOut(urlString)
    }
    
}

extension NielsenDTVRDestination: VersionedPlugin {
    public static func version() -> String {
        return __destination_version
    }
}

private struct NielsenDTVRSettings: Codable {
    let appId: String
    let sfcode: String
    let debug: Bool
}

//MARK:- Helper methods
private extension NielsenDTVRDestination {
    
    func setupEventHandlers() {
        let startHandler: SEGNielsenEventHandler = SEGNielsenEventHandler(events: ["Video Content Started"]) { nielsen, payload in
            let properties = payload?.properties
            var value = ""
            if ((properties?.dictionaryValue?["loadType"]) != nil) {
                value = properties?.dictionaryValue?["loadType"] as? String ?? ""
            }
            if ((properties?.dictionaryValue?["load_type"]) != nil) {
                value = properties?.dictionaryValue?["load_type"] as? String ?? ""
            }
            
            
            var adModel = ""
            if value == "linear" {
                adModel = "1"
            }
            if value == "dynamic" {
                adModel = "2"
            }
            
            let metadata = [
                "channelName": properties?.dictionaryValue?["channel"] as? String ?? "",
                "type": "content",
                "adModel": adModel
            ]
            
            guard let eventPayload = payload else {
                return
            }
            self.nielsenAppApi.play(self.channelInfoForPayload(event: eventPayload))
            self.nielsenAppApi.loadMetadata(metadata)
        }
        
        let playHandler: SEGNielsenEventHandler = SEGNielsenEventHandler(events: ["Video Playback Buffer Completed", "Video Playback Seek Completed", "Video Playback Resumed"]) { nielsen, payload in
            guard let eventPayload = payload else {
                return
            }
            self.nielsenAppApi.play(self.channelInfoForPayload(event: eventPayload))
        }
        
        let stopHandler: SEGNielsenEventHandler = SEGNielsenEventHandler(events:
                                                                            ["Video Playback Paused",
                                                                             "Video Playback Interrupted",
                                                                             "Video Playback Buffer Started",
                                                                             "Video Playback Seek Started",
                                                                             "Video Content Completed",
                                                                             "Application Backgrounded",
                                                                             "Video Playback Completed",
                                                                             "Video Playback Exited"]) { nielsen, payload in
            self.nielsenAppApi?.stop()
        }
        
        // This is marked as required in the destination settings
        let sendID3EventNames: [String] = defaultSettings.integrations?.dictionaryValue?["sendId3Events"] as? [String] ?? []
        
        let sendID3Handler: SEGNielsenEventHandler = SEGNielsenEventHandler(events: sendID3EventNames) { nielsen, payload in
            let id3TagPropertyKey = self.defaultSettings.integrations?.dictionaryValue?["id3Property"] as? String ?? "id3"
            let id3Tag = payload?.properties?.dictionaryValue?[id3TagPropertyKey] as? String ?? ""
            if self.lastSeenID3Tag == nil || id3Tag != self.lastSeenID3Tag {
                self.lastSeenID3Tag = id3Tag
                self.nielsenAppApi.sendID3(id3Tag)
            }
        }
        
        self.eventHandlers = [startHandler, playHandler, stopHandler, sendID3Handler]
    }
    
    func handlerEventsContainsTrackEvent(eventString: String, eventHandlerArray: [String]) ->Bool {
        if eventString == "" || eventHandlerArray.count == 0 {
            return false
        }
        
        for string in eventHandlerArray {
            if string.lowercased() == eventString.lowercased() {
                return true
            }
        }
        return false
    }
    
    /**
     Creates channel info object for the Nielsen App API's `loadMetadata` method
     @param payload Segment tracking payload
     @return NSDictionary of properties to send to the `loadMetadata` method
     */
    func channelInfoForPayload(event: TrackEvent)->[String: Any] {
        let properties = event.properties
        let channelInfo: [String: Any] = [
            "channelName": properties?.dictionaryValue?["channel"] as? String ?? "",
            "mediaURL": "",
        ]
        return channelInfo
    }
    
}

class SEGNielsenEventHandler: NSObject {
    
    var events: [String]?
    var eventHandler: ((_ nielsen: NielsenAppApi?, _ payload: TrackEvent?) -> Void)?
    /**
     Constructor method
     @param events Array of Segment event names for which to fire the block in 'eventHandler'.
     @param eventHandler Block that is intended to be executed when the appropriate Segment event is fired.
     
     @discussion
     @b nielsen Instance of the Nielsen App API - this should be passed in from the integration instance, and not retained. The instance's API methods will be invoked.
     
     @b payload Segment tracking payload.
     
     @return Instance of an event handler to map Segment events to Nielsen events.
     */
    
    public init(
        events: [String]?,
        withHandler eventHandler: @escaping (_ nielsen: NielsenAppApi?, _ payload: TrackEvent?) -> Void
    ) {
        super.init()
        self.events = events
        self.eventHandler = eventHandler
    }
}
