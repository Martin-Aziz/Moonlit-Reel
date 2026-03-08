// ContentView.swift — Root view redirect
//
// PURPOSE: Thin redirect to MainView. Preserved for SwiftUI Preview compatibility.

import SwiftUI

struct ContentView: View {
    var body: some View {
        MainView()
    }
}

#Preview {
    ContentView()
}
