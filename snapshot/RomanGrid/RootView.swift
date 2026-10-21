<<<<<<< HEAD
import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        TabView {
            SongListView()
                .tabItem { Label("Songs", systemImage: "music.note.list") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

// Global settings placeholder (theme colour by function on/off)
struct SettingsView: View {
    @AppStorage("colourByFunction") var colourByFunction: Bool = true
    var body: some View {
        Form {
            Toggle("Colour-code by function (I/ii/V…)", isOn: $colourByFunction)
            Text("Triplets and per-section tempo/time-sig are planned later.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Settings")
    }
}
=======
//
//  RootView.swift
//  RomanGrid
//
//  Created by Aidan O'Brien on 25/08/2025.
//

import Foundation
>>>>>>> 44140b1 (Initial Commit)
