import SwiftUI

extension View {
    @ViewBuilder
    func appTextInputAutocapitalizationSentences() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.sentences)
        #else
        self
        #endif
    }

    @ViewBuilder
    func appInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func appHiddenNavigationToolbarBackground() -> some View {
        #if os(iOS)
        toolbarBackground(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func appPresentationBackground(_ color: Color) -> some View {
        #if os(iOS)
        presentationBackground(color)
        #else
        self
        #endif
    }
}
