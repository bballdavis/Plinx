import PlinxUI
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Shared controls for parent-only Settings subpages.
//
// iPhone and iPad use native grouped-list controls. Apple TV never shows the
// native picker or toggle plates: a choice pushes a Plinx-styled list, and
// toggles take `PlinxSettingsToggleStyle` from `plinxSettingsChrome()`, so
// every focusable row keeps the Settings focus treatment.
// ─────────────────────────────────────────────────────────────────────────────

/// One setting chosen from a short list of values.
struct PlinxSettingsChoice<Value: Hashable>: View {
    private let title: Text
    private let systemImage: String?
    private let options: [Value]
    @Binding private var selection: Value
    private let optionLabel: (Value) -> Text

    init(
        _ title: Text,
        systemImage: String? = nil,
        selection: Binding<Value>,
        options: [Value],
        optionLabel: @escaping (Value) -> Text
    ) {
        self.title = title
        self.systemImage = systemImage
        _selection = selection
        self.options = options
        self.optionLabel = optionLabel
    }

    var body: some View {
        #if os(tvOS)
        NavigationLink {
            PlinxSettingsChoiceList(
                title: title,
                options: options,
                selection: $selection,
                optionLabel: optionLabel
            )
        } label: {
            HStack(spacing: 18) {
                label
                Spacer(minLength: 18)
                optionLabel(selection)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .plinxSettingsListButton()
        #else
        Picker(selection: $selection) {
            ForEach(options, id: \.self) { option in
                optionLabel(option).tag(option)
            }
        } label: {
            label
        }
        .pickerStyle(.menu)
        #endif
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
        } else {
            title
        }
    }
}

#if os(tvOS)
/// The values of a `PlinxSettingsChoice`, one focusable row each. Choosing a
/// value keeps the page open, like the rating chooser; Menu goes back.
private struct PlinxSettingsChoiceList<Value: Hashable>: View {
    let title: Text
    let options: [Value]
    @Binding var selection: Value
    let optionLabel: (Value) -> Text

    @FocusState private var focusedIndex: Int?

    var body: some View {
        List {
            Section {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    let isSelected = option == selection
                    Button {
                        selection = option
                    } label: {
                        HStack(spacing: 18) {
                            optionLabel(option)
                            Spacer(minLength: 18)
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .plinxSettingsListButton(isSelected: isSelected)
                    .focused($focusedIndex, equals: index)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            } header: {
                title
            }
        }
        .plinxSettingsListPage(title: title)
        .onAppear {
            focusedIndex = options.firstIndex(of: selection) ?? 0
        }
    }
}
#endif

/// A switch with an optional explanation underneath.
struct PlinxSettingsToggle: View {
    private let title: Text
    private let systemImage: String?
    @Binding private var isOn: Bool
    private let description: Text?

    init(_ title: Text, systemImage: String? = nil, isOn: Binding<Bool>, description: Text? = nil) {
        self.title = title
        self.systemImage = systemImage
        _isOn = isOn
        self.description = description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: descriptionSpacing) {
            Toggle(isOn: $isOn) {
                if let systemImage {
                    Label {
                        title
                    } icon: {
                        Image(systemName: systemImage)
                    }
                } else {
                    title
                }
            }
            #if os(tvOS)
            .plinxSettingsSingleSurfaceRow()
            #endif

            if let description {
                description
                    .font(descriptionFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    #if os(tvOS)
                    .padding(.horizontal, 22)
                    #endif
            }
        }
        #if os(tvOS)
        .listRowBackground(Color.clear)
        #endif
    }

    private var descriptionSpacing: CGFloat {
        #if os(tvOS)
        10
        #else
        6
        #endif
    }

    private var descriptionFont: Font {
        #if os(tvOS)
        .system(size: 22)
        #else
        .footnote
        #endif
    }
}

extension View {
    /// Grouped-list page treatment shared by Plinx Settings subpages.
    func plinxSettingsListPage(title: Text) -> some View {
        navigationTitle(title)
            #if os(tvOS)
            .listStyle(.plain)
            #else
            .navigationBarTitleDisplayMode(.large)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            #endif
            .background(Color.appBackground.ignoresSafeArea())
            .plinxSettingsChrome()
    }
}
