    //
//  ContentView.swift
//  TempoLab
//
//  Created by 吉田 太郎 on 2026/09/15.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            MetronomeView()
            LaunchBrandOverlay()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
