import SwiftUI

struct PairingView: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var message: String?
    @State private var working = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Logo()
                .padding(.bottom, 36)
            Text("Pair with your Mac")
                .font(.ui(34, .semibold)).tracking(-0.75)
                .foregroundStyle(Theme.text)
            Text("Click DashUp in your Mac's menu bar, choose Pair an iPad, then type the code it shows.")
                .font(.ui(16))
                .lineSpacing(5)
                .foregroundStyle(Theme.text2)
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.top, 12)

            ZStack {
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .opacity(0.01)
                    .onChange(of: code) { _, new in
                        code = String(new.filter(\.isNumber).prefix(6))
                        message = nil
                        if code.count == 6 { submit() }
                    }
                HStack(spacing: 12) {
                    ForEach(0..<6, id: \.self) { i in
                        let digit = i < code.count ? String(code[code.index(code.startIndex, offsetBy: i)]) : ""
                        Text(digit)
                            .font(.system(size: 34, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .frame(width: 64, height: 80)
                            .background(Theme.surface, in: .rect(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(i == code.count && focused ? Theme.text3 : Theme.hairline2)
                            )
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(.rect)
            .onTapGesture { focused = true }
            .padding(.top, 40)

            Group {
                if working {
                    Text("Looking for your Mac…").foregroundStyle(Theme.text2)
                } else if let message {
                    Text(message).foregroundStyle(Theme.needsText)
                } else {
                    Text("Your iPad and Mac need to be on the same network.").foregroundStyle(Theme.text3)
                }
            }
            .font(.ui(14.5))
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 120)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !working else { return }
        working = true
        focused = false
        Task {
            let result = await model.pair(code: code)
            working = false
            switch result {
            case .paired:
                break
            case .wrongCode:
                message = "That code didn't work. Check the code on your Mac and try again."
                code = ""
                focused = true
            case .noMac:
                message = "Couldn't find a Mac showing a code. Choose Pair an iPad on your Mac first."
                code = ""
                focused = true
            }
        }
    }
}

/// The DashUp mark: a monitor with the iPad beneath it.
struct Logo: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(Theme.rail)
                .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(Theme.hairline2))
            VStack(spacing: size * 0.08) {
                RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: size * 0.055)
                    .frame(width: size * 0.6, height: size * 0.36)
                RoundedRectangle(cornerRadius: size * 0.03, style: .continuous)
                    .fill(Theme.accent)
                    .frame(width: size * 0.4, height: size * 0.1)
            }
        }
        .frame(width: size, height: size)
    }
}
