//
//  SEGNielsenMainViewController.swift
//  
//
//  Created by Komal Dhingra on 01/02/23.
//

import SwiftUI
import Segment
import UIKit
import SegmentNielsenDTVR

struct SEGNielsenMainView: View {
    
    @State private var showSecondView = false
    @State var navigate = false
    @State var optOutUrl = "https://segment.com/docs/connections/destinations/catalog/nielsen-dtvr/"
    @ObservedObject var appState = AppState.shared
    
    
    var body: some View {
        NavigationView {
            VStack {
                Text("**Segment Nielsen DTVR Sample App**")
                Text("This sample application demonstrates the integration of the Nielsen App SDK and the Segment-Nielsen DTVR Integration, with a custom sample video player to monitor and track various events according to the Segment Video Spec, as it pertains to the DTVR integration. Click the 'Launch Player' button to get started.").padding(20)
                if navigate {
                    NavigationLink("WebPage", destination:  WebView(webViewModel: WebViewModel(url: optOutUrl)), isActive: $navigate)
                }
                Button {
                    self.showSecondView.toggle()
                } label: {
                    Text("Launch Player")
                }.sheet(isPresented: $showSecondView){
                    // 5. Use the new SecondView initializer
                    let videoModel = SEGVideoModel(videoId: "1234", url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4", loadType: "linear", channelName: "defaultChannel")
                    SEGNielsenVideoPlayerView(videoModel: videoModel)
                }
            }.onAppear {
                NotificationCenter.default.addObserver(forName: Notification.Name(rawValue: "io.segment.analytics.integration.did.start"), object: nil, queue: nil, using: self.integrationDidStart(_:))
            }.onDisappear {
                Analytics.main.track(name: "onDisappear")
                print("Executed Analytics onDisappear()")
            }
        }
    }
    
    
    func integrationDidStart(_ notification: Notification) {
        guard let integration = notification.object as? String else { return }
        
        if integration == "Nielsen DTVR" {
            optOutUrl = NielsenDTVRDestination().optOutURL()
            navigate = true
        }
    }
    
}

struct SEGNielsenMainView_Previews: PreviewProvider {
    static var previews: some View {
        SEGNielsenMainView()
    }
    
    
}
class AppState: ObservableObject {
    static let shared = AppState()
}
