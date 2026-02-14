//
//  ContentView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("ライブラリ", systemImage: "photo.on.rectangle")
                }

            AlbumsListView()
                .tabItem {
                    Label("アルバム", systemImage: "rectangle.stack")
                }

            TagsListView()
                .tabItem {
                    Label("タグ", systemImage: "tag")
                }

            SearchView()
                .tabItem {
                    Label("検索", systemImage: "magnifyingglass")
                }

            POIListView()
                .tabItem {
                    Label("スポット", systemImage: "mappin.and.ellipse")
                }
        }
    }
}

#Preview {
    ContentView()
}
