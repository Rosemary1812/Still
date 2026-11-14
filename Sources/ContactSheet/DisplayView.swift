import SwiftUI
import ServiceManagement

struct DisplayView: View {
    @EnvironmentObject var app: AppController
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var photos: PhotoRepository
    @EnvironmentObject var player: PlaybackController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var editing: String?
    @State private var expanded = false
    @AppStorage("showTitle") private var showTitle = true
    @AppStorage("showDescription") private var showDescription = true
    @AppStorage("showDate") private var showDate = true
    @AppStorage("showLocation") private var showLocation = true
    var body: some View {
        VStack(spacing:0) {
            if let id = player.currentID {
                ZStack(alignment:.bottom) {
                    AssetImage(id:id).id(id).transition(.opacity)
                    HStack(spacing:20) {
                        Button { player.previous() } label:{ Image(systemName:"backward.end.fill") }.help("Previous photograph")
                        Button { player.toggle() } label:{ Image(systemName:player.isPlaying ? "pause.fill" : "play.fill") }.help(player.isPlaying ? "Pause" : "Play")
                        Button { player.next() } label:{ Image(systemName:"forward.end.fill") }.help("Next photograph")
                        Menu { Button("Edit Details") { player.pause(); editing = id }; Toggle("Shuffle",isOn:$player.shuffle); Button("Hide Display") { app.hideDisplay() } } label:{ Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).frame(width:22)
                    }.buttonStyle(.plain).padding(.horizontal,16).padding(.vertical,12).background(.regularMaterial,in:Capsule()).padding(14).opacity(hovering ? 1 : 0)
                    .accessibilityHidden(!hovering)
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                annotation(id)
            } else { ContentUnavailableView("An album for your desktop",systemImage:"rectangle.stack",description:Text("Choose Play Album from your library to begin.")) }
        }.padding(.top,24).background(.background)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration:0.35),value:player.currentID)
        .focusable().focusEffectDisabled()
        .onKeyPress(.leftArrow) { player.previous(); return .handled }
        .onKeyPress(.rightArrow) { player.next(); return .handled }
        .onKeyPress(.space) { player.toggle(); return .handled }
        .onChange(of:player.currentID) { _,_ in expanded = false }
        .sheet(item:Binding(get:{ editing.map { PhotoEditTarget(id:$0) } },set:{ editing = $0?.id })) { target in AnnotationEditor(id:target.id) }
        .task(id:"\(player.currentID ?? "")-\(photos.revision)") {
            guard let id = player.currentID, let index = player.ids.firstIndex(of:id), player.ids.count > 1 else { return }
            let next = player.ids[(index+1) % player.ids.count]
            _ = await photos.loadImage(id:next,size:CGSize(width:1000,height:1000))
        }
    }
    @ViewBuilder func annotation(_ id:String) -> some View {
        let saved = store.annotation(id:id)
        let metadata = photos.metadata(id:id)
        let date = saved == nil ? metadata?.date : saved?.displayDate
        let location = saved == nil ? metadata?.location : saved?.locationText.nonEmpty
        let title = showTitle ? saved?.title.nonEmpty : nil
        let description = showDescription ? saved?.descriptionText.nonEmpty : nil
        if title != nil || description != nil || (showDate && date != nil) || (showLocation && location != nil) {
            VStack(alignment:.leading,spacing:7) {
                if let title { Text(title).font(.system(size:19,weight:.medium,design:.serif)).lineLimit(2) }
                HStack { if showDate, let date { Text(date,format:.dateTime.month(.wide).day().year()) }; if showLocation, let location { Text(location) } }.font(.caption).foregroundStyle(.secondary)
                if let description {
                    ScrollView { Text(description).font(.callout).lineSpacing(3).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled) }.frame(maxHeight:expanded ? 200 : 72)
                    if description.count > 140 { Button(expanded ? "Show less" : "Read more") { expanded.toggle() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary) }
                }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(18)
        }
    }
}
struct AnnotationEditor: View {
    let id:String
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var photos: PhotoRepository
    @EnvironmentObject var player: PlaybackController
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var story = ""
    @State private var date = Date()
    @State private var hasDate = true
    @State private var location = ""
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("照片旁边的故事").font(.title2.weight(.medium)); Spacer() }
            HStack(alignment:.top,spacing:22) {
                AssetImage(id:id).frame(width:200,height:280)
                VStack(alignment:.leading,spacing:12) {
                    TextField("标题",text:$title).textFieldStyle(.roundedBorder)
                    Text("描述").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text:$story).frame(height:130).border(Color.secondary.opacity(0.2))
                    Toggle("显示日期",isOn:$hasDate)
                    if hasDate { DatePicker("Date",selection:$date,displayedComponents:.date).labelsHidden() }
                    TextField("地点",text:$location).textFieldStyle(.roundedBorder)
                }
            }
            Text("这张照片在不同相册中共享同一份描述，不会修改原始照片。").font(.caption).foregroundStyle(.secondary)
            HStack { Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("保存") { store.saveAnnotation(id:id,title:title,description:story,date:hasDate ? date : nil,location:location); if store.error == nil { dismiss() } }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(24).frame(width:640)
        .onAppear { player.pause(); if let item = store.annotation(id:id) { title = item.title; story = item.descriptionText; hasDate = item.displayDate != nil; date = item.displayDate ?? Date(); location = item.locationText } else { let info = photos.metadata(id:id); hasDate = info?.date != nil; date = info?.date ?? Date(); location = info?.location ?? "" } }
    }
}
struct PreferencesView: View {
    @EnvironmentObject var player: PlaybackController
    @AppStorage("autoPlay") private var autoPlay = true
    @AppStorage("showTitle") private var showTitle = true
    @AppStorage("showDescription") private var showDescription = true
    @AppStorage("showDate") private var showDate = true
    @AppStorage("showLocation") private var showLocation = true
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var error: String?
    var body: some View {
        Form {
            Section("Playback") { Picker("Interval",selection:$player.interval) { Text("15 seconds").tag(15.0); Text("30 seconds").tag(30.0); Text("1 minute").tag(60.0); Text("5 minutes").tag(300.0); Text("15 minutes").tag(900.0) }; Toggle("Shuffle",isOn:$player.shuffle); Toggle("Play when opening an album",isOn:$autoPlay) }
            Section("Photo details") { Toggle("Title",isOn:$showTitle); Toggle("Description",isOn:$showDescription); Toggle("Date",isOn:$showDate); Toggle("Location",isOn:$showLocation) }
            Section("System") { Toggle("Launch at login",isOn:$login).onChange(of:login) { _,value in do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { self.error = "Could not change login item: \(error.localizedDescription)"; login = SMAppService.mainApp.status == .enabled } }; if let error { Text(error).font(.caption).foregroundStyle(.red) } }
        }.formStyle(.grouped)
    }
}
