//
//  ContentView.swift
//  StockManager
//
//  Created by MOROZUMI Shunsuke on 2026/04/01.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private enum StockManagerTheme {
    static let page = Color(red: 0.985, green: 0.982, blue: 0.992)
    static let surface = Color.white
    static let lavender = Color(red: 0.47, green: 0.35, blue: 0.76)
    static let lavenderSoft = Color(red: 0.93, green: 0.90, blue: 0.97)
    static let lavenderSurface = Color(red: 0.96, green: 0.94, blue: 0.98)
    static let shadow = Color.black.opacity(0.10)
    static let highlightedFill = Color(red: 1.0, green: 0.97, blue: 0.77)
    static let highlightedStroke = Color(red: 0.98, green: 0.85, blue: 0.32)
    static let highlightedText = Color(red: 0.88, green: 0.56, blue: 0.10)
    static let outFill = Color(red: 0.97, green: 0.86, blue: 0.86)
    static let outText = Color(red: 0.82, green: 0.31, blue: 0.26)
    static let stockStroke = Color.black.opacity(0.10)
}

struct ContentView: View {
    @EnvironmentObject private var store: StockManagerStore
    @Environment(\.openURL) private var openURL

    @State private var tutorialFrames: [TutorialTargetID: CGRect] = [:]
    @State private var boardFormState: BoardFormState?
    @State private var itemFormState: ItemFormState?
    @State private var infoSheetKind: InfoSheetKind?
    @State private var exportDocument = BoardTransferDocument()
    @State private var exportFilename = "stockmanager.json"
    @State private var exportContentType: UTType = .json
    @State private var exportPresented = false
    @State private var importPresented = false
    @State private var deleteAllPresented = false
    @State private var pendingBoardDeletion: Board?
    @State private var pendingItemDeletion: StockItem?
    @State private var discardShoppingPresented = false
    @State private var errorMessage: String?
    @State private var visibleBanner: String?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack(alignment: .leading) {
            backgroundView

            if store.hasLoadedInitialState {
                loadedContent
            } else {
                loadingView
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.drawerOpen)
        .animation(.easeInOut(duration: 0.2), value: store.shoppingState != nil)
        .task {
            store.loadInitialStateIfNeeded()
        }
        .sheet(item: $infoSheetKind) { kind in
            InfoTextSheet(kind: kind)
        }
        .sheet(isPresented: $deleteAllPresented) {
            DeleteAllDataSheet {
                store.resetAllData()
                deleteAllPresented = false
            }
        }
        .fileExporter(
            isPresented: $exportPresented,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { result in
            if case let .failure(error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $importPresented,
            allowedContentTypes: [.json, .commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else {
                    return
                }
                importBoard(from: url)
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("エラー", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("ボードを削除しますか？", isPresented: pendingBoardDeletionBinding) {
            Button("削除", role: .destructive) {
                if let board = pendingBoardDeletion {
                    store.deleteBoard(id: board.id)
                }
                pendingBoardDeletion = nil
            }
            Button("キャンセル", role: .cancel) {
                pendingBoardDeletion = nil
            }
        } message: {
            Text("「\(pendingBoardDeletion?.name ?? "")」と配下のアイテムを削除します。")
        }
        .alert("アイテムを削除しますか？", isPresented: pendingItemDeletionBinding) {
            Button("削除", role: .destructive) {
                if let item = pendingItemDeletion {
                    store.deleteItem(id: item.id)
                }
                pendingItemDeletion = nil
            }
            Button("キャンセル", role: .cancel) {
                pendingItemDeletion = nil
            }
        } message: {
            Text("「\(pendingItemDeletion?.name ?? "")」を削除します。")
        }
        .alert("未保存の変更を破棄しますか？", isPresented: $discardShoppingPresented) {
            Button("破棄", role: .destructive) {
                store.closeShoppingOverlayDiscardingChanges()
            }
            Button("キャンセル", role: .cancel) {
            }
        } message: {
            Text("買い物リスト内の変更は保存されません。")
        }
        .onChange(of: store.bannerMessage) { _, newValue in
            guard let newValue else {
                return
            }
            withAnimation(.spring(duration: 0.25)) {
                visibleBanner = newValue
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.2))
                if visibleBanner == newValue {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        visibleBanner = nil
                    }
                    store.bannerMessage = nil
                }
            }
        }
    }

    private var loadedContent: some View {
        ZStack(alignment: .leading) {
            mainContent
                .coordinateSpace(name: "StockManagerRootSpace")
                .onPreferenceChange(TutorialTargetPreferenceKey.self) { tutorialFrames = $0 }
                .disabled(
                    store.drawerOpen ||
                    store.shoppingState != nil ||
                    store.tutorialIsPresented ||
                    boardFormState != nil ||
                    itemFormState != nil
                )
                .blur(radius: store.drawerOpen ? 1.5 : 0)

            if store.drawerOpen {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.drawerOpen = false
                            store.boardEditMode = false
                        }
                    }

                DrawerPanel(
                    onExportJSON: { prepareExport(.json) },
                    onExportCSV: { prepareExport(.csv) },
                    onImport: { importPresented = true },
                    onOpenTemplate: { openExternalURL("https://morosy.github.io/sm_template_maker.html") },
                    onOpenContact: { openExternalURL("https://morosy.github.io/contact.html") },
                    onOpenTutorial: { store.startTutorial() },
                    onOpenInfo: { infoSheetKind = $0 },
                    onAddBoard: { boardFormState = BoardFormState(mode: .add, initialName: "") },
                    onDeleteBoard: { pendingBoardDeletion = $0 },
                    onDeleteAll: { deleteAllPresented = true }
                )
                .environmentObject(store)
                .frame(maxWidth: 360)
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(1)
            }

            if store.shoppingState != nil {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if store.shoppingHasUnsavedChanges() {
                            discardShoppingPresented = true
                        } else {
                            store.closeShoppingOverlayDiscardingChanges()
                        }
                    }

                ShoppingListOverlay()
                    .environmentObject(store)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 32)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(2)
            }

            if let step = store.currentTutorialStep {
                TutorialOverlay(
                    step: step,
                    stepIndex: store.tutorialStepIndex,
                    stepCount: store.tutorialSteps.count,
                    targetFrame: step.target.flatMap { tutorialFrames[$0] },
                    onSkip: { store.stopTutorial() },
                    onBack: { store.previousTutorialStep() },
                    onNext: { store.nextTutorialStep() }
                )
                .zIndex(3)
            }

            if let boardFormState {
                modalScrim
                    .onTapGesture {
                        self.boardFormState = nil
                    }
                    .zIndex(3)

                BoardFormDialog(
                    state: boardFormState,
                    onClose: {
                        self.boardFormState = nil
                    },
                    onSave: { name in
                        do {
                            if boardFormState.mode == .add {
                                try store.addBoard(named: name)
                            } else {
                                try store.renameCurrentBoard(to: name)
                            }
                            self.boardFormState = nil
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                )
                .padding(.horizontal, 36)
                .zIndex(4)
            }

            if let itemFormState {
                modalScrim
                    .onTapGesture {
                        self.itemFormState = nil
                    }
                    .zIndex(3)

                ItemFormDialog(
                    state: itemFormState,
                    onClose: {
                        self.itemFormState = nil
                    },
                    onSave: { name in
                        do {
                            switch itemFormState.mode {
                            case .add:
                                try store.addItem(named: name)
                            case let .edit(itemID):
                                try store.renameItem(id: itemID, to: name)
                            }
                            self.itemFormState = nil
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                )
                .padding(.horizontal, 36)
                .zIndex(4)
            }

            if let visibleBanner {
                VStack {
                    Text(visibleBanner)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.black.opacity(0.82)))
                        .padding(.top, 16)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(5)
            }
        }
    }

    private var backgroundView: some View {
        StockManagerTheme.page
        .ignoresSafeArea()
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(StockManagerTheme.lavender)
            Text("読み込み中...")
                .font(.headline.weight(.semibold))
                .foregroundStyle(StockManagerTheme.lavender)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var modalScrim: some View {
        Color.black.opacity(0.42)
            .ignoresSafeArea()
    }

    private var mainContent: some View {
        VStack(spacing: 14) {
            topBar
            controlArea
            if store.itemEditMode {
                Text("編集モード: カードをタップして名前変更、右上の x で削除")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(StockManagerTheme.lavender)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            boardContent
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.drawerOpen.toggle()
                    if store.drawerOpen == false {
                        store.boardEditMode = false
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tutorialTarget(.menuButton)
            .accessibilityIdentifier("menuButton")

            Button {
                boardFormState = BoardFormState(mode: .rename, initialName: store.currentBoard?.name ?? "")
            } label: {
                Text(store.currentBoard?.name ?? "ボードなし")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .tutorialTarget(.boardTitle)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.searchOpen.toggle()
                }
            } label: {
                Image(systemName: store.searchOpen ? "xmark" : "magnifyingglass")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("searchButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(StockManagerTheme.lavenderSurface)
        )
    }

    private var controlArea: some View {
        VStack(spacing: 12) {
            if store.searchOpen {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(StockManagerTheme.lavender)
                    TextField(
                        "アイテムを検索",
                        text: Binding(
                            get: { store.settings.query },
                            set: { store.setQuery($0) }
                        )
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    if store.settings.query.isEmpty == false {
                        Button {
                            store.setQuery("")
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(StockManagerTheme.surface)
                        .shadow(color: StockManagerTheme.shadow, radius: 10, x: 0, y: 6)
                )
            }

            HStack(spacing: 10) {
                ToggleChip(
                    title: "在庫",
                    isOn: store.settings.showStock,
                    tint: StockManagerTheme.lavender
                ) {
                    store.setShowStock(!store.settings.showStock)
                }
                ToggleChip(
                    title: "欠品",
                    isOn: store.settings.showOut,
                    tint: StockManagerTheme.lavender
                ) {
                    store.setShowOut(!store.settings.showOut)
                }
            }
            .tutorialTarget(.filterRow)

            HStack(spacing: 10) {
                Menu {
                    ForEach(SortMode.allCases) { mode in
                        Button(mode.title) {
                            store.setSortMode(mode)
                        }
                    }
                } label: {
                    HStack {
                        Text(store.currentSortMode.title)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(StockManagerTheme.lavender)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        Capsule(style: .continuous)
                            .fill(StockManagerTheme.lavenderSurface)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    store.toggleSortModePair()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(StockManagerTheme.lavender)
                        .frame(width: 44, height: 44)
                        .background(
                            Capsule(style: .continuous)
                                .fill(StockManagerTheme.lavenderSurface)
                        )
                }
                .buttonStyle(.plain)
            }
            .tutorialTarget(.sortButton)
        }
    }

    private var boardContent: some View {
        Group {
            if store.sortedBoards.isEmpty {
                EmptyStateView(
                    title: "ボードがありません",
                    message: "メニューからボードを追加してください。"
                )
            } else if store.currentBoardItems.isEmpty {
                EmptyStateView(
                    title: "アイテムがありません",
                    message: "右下の追加ボタンから最初のアイテムを作成しましょう。"
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(Array(store.currentBoardItems.enumerated()), id: \.element.id) { index, item in
                            ItemCardView(
                                item: item,
                                isEditing: store.itemEditMode,
                                isTutorialTarget: index == 0,
                                onTap: {
                                    if store.itemEditMode {
                                        itemFormState = ItemFormState(mode: .edit(item.id), initialName: item.name)
                                    } else {
                                        withAnimation(.spring(duration: 0.28)) {
                                            store.toggleStatus(for: item.id)
                                        }
                                    }
                                },
                                onDelete: {
                                    pendingItemDeletion = item
                                }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }
                    }
                    .padding(.bottom, 18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(duration: 0.3), value: store.currentBoardItems.map(\.id))
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if store.itemEditMode {
                Spacer()
                Button {
                    store.itemEditMode = false
                } label: {
                    Text("編集完了")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: 220)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(StockManagerTheme.lavender)
                        )
                }
                .buttonStyle(.plain)
                Spacer()
            } else {
                ActionFAB(
                    title: "",
                    systemName: "pencil",
                    tint: StockManagerTheme.lavender
                ) {
                    store.itemEditMode = true
                }
                .tutorialTarget(.itemEditButton)

                Button {
                    store.openShoppingOverlay()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "cart")
                        Text("買い物リスト")
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        Capsule()
                            .fill(StockManagerTheme.lavender)
                    )
                }
                .buttonStyle(.plain)
                .tutorialTarget(.shoppingButton)

                ActionFAB(
                    title: "",
                    systemName: "plus",
                    tint: StockManagerTheme.lavender
                ) {
                    itemFormState = ItemFormState(mode: .add, initialName: "")
                }
                .tutorialTarget(.itemAddButton)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(StockManagerTheme.surface)
                .shadow(color: StockManagerTheme.shadow, radius: 12, x: 0, y: 5)
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if $0 == false { errorMessage = nil } }
        )
    }

    private var pendingBoardDeletionBinding: Binding<Bool> {
        Binding(
            get: { pendingBoardDeletion != nil },
            set: { if $0 == false { pendingBoardDeletion = nil } }
        )
    }

    private var pendingItemDeletionBinding: Binding<Bool> {
        Binding(
            get: { pendingItemDeletion != nil },
            set: { if $0 == false { pendingItemDeletion = nil } }
        )
    }

    private func openExternalURL(_ rawValue: String) {
        guard let url = URL(string: rawValue) else {
            return
        }
        openURL(url)
    }

    private func prepareExport(_ format: TransferFormat) {
        do {
            let result = try store.previewExport(format: format)
            exportDocument = result.document
            exportFilename = result.filename
            exportContentType = format == .json ? .json : .commaSeparatedText
            exportPresented = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importBoard(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let type = UTType(filenameExtension: url.pathExtension)
            let payload = try store.importExportService.importBoard(
                data: data,
                contentType: type,
                fileExtension: url.pathExtension
            )
            store.importBoard(payload: payload)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DrawerPanel: View {
    @EnvironmentObject private var store: StockManagerStore

    let onExportJSON: () -> Void
    let onExportCSV: () -> Void
    let onImport: () -> Void
    let onOpenTemplate: () -> Void
    let onOpenContact: () -> Void
    let onOpenTutorial: () -> Void
    let onOpenInfo: (InfoSheetKind) -> Void
    let onAddBoard: () -> Void
    let onDeleteBoard: (Board) -> Void
    let onDeleteAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ボード")
                        .font(.title3.weight(.bold))
                }
                Spacer()
                menuButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)

            List {
                ForEach(store.sortedBoards) { board in
                    BoardRow(
                        board: board,
                        isCurrent: store.currentBoard?.id == board.id,
                        isEditing: store.boardEditMode,
                        onTap: {
                            if store.boardEditMode == false {
                                store.setCurrentBoard(board.id)
                            }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .tutorialTarget(.boardTarget(for: board, currentBoardID: store.currentBoard?.id))
                    .overlay(alignment: .trailing) {
                        if store.boardEditMode {
                            Button(role: .destructive) {
                                onDeleteBoard(board)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 12)
                        }
                    }
                }
                .onMove(perform: store.moveBoards)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            #if os(iOS)
            .environment(\.editMode, .constant(store.boardEditMode ? .active : .inactive))
            #endif
            .tutorialTarget(.boardList)

            drawerBottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(StockManagerTheme.page)
        )
        .shadow(color: StockManagerTheme.shadow, radius: 12, x: 4, y: 0)
    }

    private var menuButton: some View {
        Menu {
            Button("JSON エクスポート") {
                onExportJSON()
            }
            Button("CSV エクスポート") {
                onExportCSV()
            }
            Button("インポート") {
                onImport()
            }
            Divider()
            Button("外部ツールからボード作成") {
                onOpenTemplate()
            }
            Button("使い方") {
                onOpenTutorial()
            }
            Button("問い合わせ") {
                onOpenContact()
            }
            Divider()
            Button("About") {
                onOpenInfo(.about)
            }
            Button("利用規約") {
                onOpenInfo(.terms)
            }
            Button("OSS ライセンス") {
                onOpenInfo(.oss)
            }
            Button("プライバシーポリシー") {
                onOpenInfo(.privacy)
            }
            Divider()
            Button("データ削除", role: .destructive) {
                onDeleteAll()
            }
        } label: {
            Image(systemName: "ellipsis.vertical")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }

    private var drawerBottomBar: some View {
        VStack(spacing: 10) {
            if store.boardEditMode {
                Button {
                    onAddBoard()
                } label: {
                    drawerActionLabel("ボード追加", systemName: "plus")
                }
                .buttonStyle(.plain)
                .tutorialTarget(.boardAddButton)

                Button {
                    store.boardEditMode = false
                } label: {
                    drawerActionLabel("編集完了", systemName: "checkmark")
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    store.boardEditMode = true
                } label: {
                    drawerActionLabel("ボード編集", systemName: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .tutorialTarget(.boardEditButton)
            }
        }
        .padding(16)
        .overlay(alignment: .top) {
            Divider()
                .padding(.horizontal, 8)
        }
    }

    private func drawerActionLabel(_ title: String, systemName: String) -> some View {
        HStack {
            Image(systemName: systemName)
            Text(title)
                .fontWeight(.semibold)
            Spacer()
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(StockManagerTheme.lavenderSurface)
        )
    }
}

private struct BoardRow: View {
    let board: Board
    let isCurrent: Bool
    let isEditing: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 12) {
                if isEditing {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                }
                Text(board.name)
                    .font(.headline)
                    .foregroundStyle(isCurrent ? .white : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isCurrent && isEditing == false {
                    EmptyView()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isCurrent
                        ? StockManagerTheme.lavender
                        : StockManagerTheme.lavenderSurface
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isEditing)
    }
}

private struct ShoppingListOverlay: View {
    @EnvironmentObject private var store: StockManagerStore

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                if store.shoppingState?.stage == .result {
                    Button("戻る") {
                        store.goBackToShoppingSelection()
                    }
                } else {
                    Color.clear.frame(width: 44)
                }
                Spacer()
                Text("買い物リスト")
                    .font(.title3.weight(.bold))
                Spacer()
                Button("閉じる") {
                    if store.shoppingState?.stage == .result {
                        store.saveShoppingChanges()
                    } else {
                        store.closeShoppingOverlayDiscardingChanges()
                    }
                }
            }

            if store.shoppingState?.stage == .boardSelection {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(store.sortedBoards) { board in
                            Button {
                                store.toggleShoppingBoard(board.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(board.name)
                                            .font(.headline)
                                        Text("\(store.visibleItems(for: board.id).count) 件")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: store.shoppingState?.selectedBoardIDs.contains(board.id) == true ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(
                                            store.shoppingState?.selectedBoardIDs.contains(board.id) == true
                                            ? Color.accentColor
                                            : Color.secondary
                                        )
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.primary.opacity(0.06))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    store.proceedShoppingSelection()
                } label: {
                    Text("結果を見る")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(
                                    store.shoppingState?.selectedBoardIDs.isEmpty == false
                                    ? Color(red: 0.79, green: 0.52, blue: 0.16)
                                    : Color.secondary
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(store.shoppingState?.selectedBoardIDs.isEmpty ?? true)
            } else {
                if store.shoppingSections().isEmpty {
                    Spacer()
                    Text("選択したボードに買い物対象のアイテムがありません。")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(store.shoppingSections(), id: \.board.id) { section in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(section.board.name)
                                        .font(.headline.weight(.bold))
                                    LazyVGrid(columns: columns, spacing: 10) {
                                        ForEach(section.items) { item in
                                            Button {
                                                withAnimation(.spring(duration: 0.24)) {
                                                    store.cycleShoppingStatus(for: item.id)
                                                }
                                            } label: {
                                                Text(item.name)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(Color.primary)
                                                    .multilineTextAlignment(.center)
                                                    .frame(maxWidth: .infinity, minHeight: 72)
                                                    .padding(.horizontal, 10)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                            .fill(shoppingCardColor(item.itemStatus))
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 640, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    private func shoppingCardColor(_ status: ItemStatus) -> Color {
        switch status {
        case .inStock:
            return .platformSecondarySystemBackground
        case .highlighted:
            return Color(red: 1.0, green: 0.97, blue: 0.77)
        case .outOfStock:
            return Color(red: 0.98, green: 0.87, blue: 0.86)
        }
    }
}

private struct TutorialOverlay: View {
    let step: TutorialStep
    let stepIndex: Int
    let stepCount: Int
    let targetFrame: CGRect?
    let onSkip: () -> Void
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    if let targetFrame {
                        path.addRoundedRect(
                            in: targetFrame.insetBy(dx: -10, dy: -10),
                            cornerSize: CGSize(width: 22, height: 22)
                        )
                    }
                }
                .fill(Color.black.opacity(0.72), style: FillStyle(eoFill: true))
                .ignoresSafeArea()

                if let targetFrame {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.95), lineWidth: 2)
                        .frame(width: targetFrame.width + 20, height: targetFrame.height + 20)
                        .position(x: targetFrame.midX, y: targetFrame.midY)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("\(stepIndex + 1) / \(stepCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("スキップ") {
                            onSkip()
                        }
                        .font(.subheadline.weight(.semibold))
                    }

                    Text(step.title)
                        .font(.title3.weight(.bold))
                    Text(step.message)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("戻る") {
                            onBack()
                        }
                        .disabled(stepIndex == 0)

                        Spacer()

                        Button(stepIndex + 1 == stepCount ? "完了" : "次へ") {
                            onNext()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.platformSystemBackground)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, max(24, proxy.safeAreaInsets.bottom + 8))
            }
        }
    }
}

private struct ItemCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: StockItem
    let isEditing: Bool
    let isTutorialTarget: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var wobble = false

    var body: some View {
        Button {
            onTap()
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(cardColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1.2)
                    )
                    .shadow(color: StockManagerTheme.shadow, radius: 6, x: 0, y: 3)

                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(item.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 98, maxHeight: 98)
                .padding(.horizontal, 12)

                if isEditing {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red, .white)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .buttonStyle(.plain)
        .rotationEffect(isEditing ? Angle(degrees: wobble ? 1.2 : -1.2) : .zero)
        .animation(isEditing ? .easeInOut(duration: 0.16).repeatForever(autoreverses: true) : .easeInOut(duration: 0.16), value: wobble)
        .onAppear {
            wobble = isEditing
        }
        .onChange(of: isEditing) { _, newValue in
            wobble = newValue
        }
        .tutorialTarget(isTutorialTarget ? .currentItem : nil)
    }

    private var cardColor: Color {
        switch (colorScheme, item.itemStatus) {
        case (.light, .inStock):
            return StockManagerTheme.surface
        case (.light, .highlighted):
            return StockManagerTheme.highlightedFill
        case (.light, .outOfStock):
            return StockManagerTheme.outFill
        case (.dark, .inStock):
            return Color(red: 0.18, green: 0.18, blue: 0.22)
        case (.dark, .highlighted):
            return Color(red: 0.39, green: 0.34, blue: 0.16)
        case (.dark, .outOfStock):
            return Color(red: 0.40, green: 0.18, blue: 0.20)
        @unknown default:
            return Color.white
        }
    }

    private var borderColor: Color {
        switch item.itemStatus {
        case .inStock:
            return StockManagerTheme.stockStroke
        case .highlighted:
            return StockManagerTheme.highlightedStroke
        case .outOfStock:
            return StockManagerTheme.outFill
        }
    }

    private var titleColor: Color {
        switch item.itemStatus {
        case .inStock:
            return .primary
        case .highlighted:
            return StockManagerTheme.highlightedText
        case .outOfStock:
            return StockManagerTheme.outText
        }
    }
}

private struct ToggleChip: View {
    let title: String
    let isOn: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(isOn ? .white : StockManagerTheme.lavender)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? tint : StockManagerTheme.lavenderSoft)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ActionFAB: View {
    let title: String
    let systemName: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(Circle().fill(tint))
            .shadow(color: StockManagerTheme.shadow, radius: 8, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyStateView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.grid.2x2")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.bold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct BoardFormDialog: View {
    let state: BoardFormState
    let onClose: () -> Void
    let onSave: (String) -> Void

    @State private var name: String

    init(state: BoardFormState, onClose: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.state = state
        self.onClose = onClose
        self.onSave = onSave
        self._name = State(initialValue: state.initialName)
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(state.mode == .add ? "追加" : "ボード名")
                    .font(.title3.weight(.bold))
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("名前")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StockManagerTheme.lavender)
                TextField("名前を入力", text: $name)
                    .onChange(of: name) { _, newValue in
                        name = newValue.limited(to: 10)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(StockManagerTheme.lavender, lineWidth: 1.4)
                    )
                HStack {
                    Spacer()
                    Text("\(name.count)/10")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                onSave(name)
            } label: {
                Text("保存")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(name.trimmed().isEmpty ? StockManagerTheme.lavender.opacity(0.35) : StockManagerTheme.lavender)
                    )
            }
            .buttonStyle(.plain)
            .disabled(name.trimmed().isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(StockManagerTheme.surface)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 14)
    }
}

private struct ItemFormDialog: View {
    let state: ItemFormState
    let onClose: () -> Void
    let onSave: (String) -> Void

    @State private var name: String

    init(state: ItemFormState, onClose: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.state = state
        self.onClose = onClose
        self.onSave = onSave
        self._name = State(initialValue: state.initialName)
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(state.mode.title)
                    .font(.title3.weight(.bold))
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("名前")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StockManagerTheme.lavender)
                TextField("名前を入力", text: $name)
                    .onChange(of: name) { _, newValue in
                        name = newValue.limited(to: 24)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(StockManagerTheme.lavender, lineWidth: 1.4)
                    )
                HStack {
                    Spacer()
                    Text("\(name.count)/24")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                onSave(name)
            } label: {
                Text("保存")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(name.trimmed().isEmpty ? StockManagerTheme.lavender.opacity(0.35) : StockManagerTheme.lavender)
                    )
            }
            .buttonStyle(.plain)
            .disabled(name.trimmed().isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(StockManagerTheme.surface)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 14)
    }
}

private struct DeleteAllDataSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onConfirm: () -> Void

    @State private var isSecondStep = false
    @State private var confirmationText = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                if isSecondStep {
                    Text("確認のため `delete` と入力してください。")
                        .font(.headline)
                    TextField("delete", text: $confirmationText)
                        .textFieldStyle(.roundedBorder)
                    Text("実行すると全データを削除し、初回起動状態へ戻します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("保存済みのボード、アイテム、設定をすべて削除します。")
                        .font(.headline)
                    Text("削除後は初期ボードと初期アイテムを再作成し、チュートリアルも再表示します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("データ削除")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSecondStep ? "削除する" : "次へ") {
                        if isSecondStep {
                            onConfirm()
                        } else {
                            isSecondStep = true
                        }
                    }
                    .disabled(isSecondStep && confirmationText != "delete")
                    .tint(.red)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct InfoTextSheet: View {
    @Environment(\.dismiss) private var dismiss

    let kind: InfoSheetKind

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(kind.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .navigationTitle(kind.title)
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct BoardFormState: Identifiable {
    enum Mode: Equatable {
        case add
        case rename
    }

    let id = UUID()
    let mode: Mode
    let initialName: String
}

private struct ItemFormState: Identifiable {
    enum Mode: Equatable {
        case add
        case edit(Int64)

        var title: String {
            switch self {
            case .add:
                return "アイテム追加"
            case .edit:
                return "アイテム名変更"
            }
        }
    }

    let id = UUID()
    let mode: Mode
    let initialName: String
}

private struct TutorialTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [TutorialTargetID: CGRect] = [:]

    static func reduce(value: inout [TutorialTargetID: CGRect], nextValue: () -> [TutorialTargetID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct TutorialTargetModifier: ViewModifier {
    let target: TutorialTargetID?

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TutorialTargetPreferenceKey.self,
                    value: target.map {
                        [$0: proxy.frame(in: .named("StockManagerRootSpace"))]
                    } ?? [:]
                )
            }
        }
    }
}

private extension View {
    func tutorialTarget(_ target: TutorialTargetID?) -> some View {
        modifier(TutorialTargetModifier(target: target))
    }

    func platformInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

private extension Color {
    static var platformSystemBackground: Color {
        #if os(iOS)
        Color(uiColor: UIColor.systemBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var platformSecondarySystemBackground: Color {
        #if os(iOS)
        Color(uiColor: UIColor.secondarySystemBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

private extension TutorialTargetID {
    static func boardTarget(for board: Board, currentBoardID: Int64?) -> TutorialTargetID? {
        if board.id == currentBoardID {
            return .currentBoardRow
        }
        return nil
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(StockManagerStore(preview: true))
    }
}
