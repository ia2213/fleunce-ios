import SwiftUI
import FluenceCore

// MARK: - Parental Gate (Apple Guideline 1.3 Compliant)
// Equation-based gate: the parent must solve a math problem to access
// parental settings / exit Kids Mode. No default PIN — no bypass.
struct ParentalGateView: View {
    var coordinator: ConversationCoordinator
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme

    @State private var equation: Equation = Equation(first: 3, second: 7, third: 2, op1: .plus, op2: .times)
    @State private var options: [Int] = []
    @State private var selectedAnswer: Int?
    @State private var showFeedback: Bool = false
    @State private var feedbackCorrect: Bool = false
    @State private var currentStreak = 0

    private static let supportedOps: [Operator] = [.plus, .minus, .times]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0F172A").ignoresSafeArea()

                VStack(spacing: 28) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.cyan)
                            .padding(.top, 12)

                        Text("Contrôle Parental")
                            .font(.title2.bold())
                            .foregroundStyle(.white)

                        Text("Résolvez l'équation pour accéder aux réglages")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 8)

                    Divider()
                        .background(Color.white.opacity(0.15))
                        .padding(.horizontal, 32)

                    // Equation display
                    VStack(spacing: 16) {
                        Text(equation.displayText)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)

                        Text("= ?")
                            .font(.title.bold())
                            .foregroundStyle(.yellow)
                    }
                    .padding(.vertical, 12)

                    // Feedback overlay
                    if showFeedback {
                        HStack(spacing: 10) {
                            Image(systemName: feedbackCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(feedbackCorrect ? .green : .red)
                            Text(feedbackCorrect ? "Correct !" : "Incorrect, réessayez.")
                                .font(.headline)
                                .foregroundStyle(feedbackCorrect ? .green : .red)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(feedbackCorrect ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                        )
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Answer options grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(options, id: \.self) { value in
                            Button {
                                if showFeedback { return }
                                selectedAnswer = value
                                let correct = (value == equation.result)
                                feedbackCorrect = correct
                                showFeedback = true
                                if correct {
                                    currentStreak += 1
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                                        unlockParentalAccess()
                                    }
                                } else {
                                    currentStreak = 0
                                    selectedAnswer = nil
                                    // Regenerate after a short delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            generateNewEquation()
                                        }
                                        showFeedback = false
                                        selectedAnswer = nil
                                    }
                                }
                            } label: {
                                Text("\(value)")
                                    .font(.title.bold())
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 64)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(
                                                selectedAnswer == value
                                                    ? (feedbackCorrect ? Color.green.opacity(0.3) : Color.white.opacity(0.12))
                                                    : Color.white.opacity(0.07)
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(
                                                selectedAnswer == value
                                                    ? (feedbackCorrect ? Color.green : Color.white.opacity(0.4))
                                                    : Color.white.opacity(0.08),
                                                lineWidth: 2
                                            )
                                    )
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .disabled(showFeedback && feedbackCorrect)
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Anti-brute-force notice
                    if currentStreak == 0 && showFeedback && !feedbackCorrect {
                        Text("Nouveaux calcul après chaque erreur")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.7))
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        isPresented = false
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .onAppear {
            generateNewEquation()
        }
    }

    // MARK: - Equation Logic

    private func generateNewEquation() {
        var first = Int.random(in: 2...12)
        var second = Int.random(in: 2...12)
        let third = Int.random(in: 1...9)
        let op1 = Self.supportedOps.randomElement()!
        let op2: Operator = .plus

        if op1 == .minus && first < second {
            swap(&first, &second)
        }

        equation = Equation(first: first, second: second, third: third, op1: op1, op2: op2)
        options = generateOptions(correct: equation.result)
        selectedAnswer = nil
        showFeedback = false
        currentStreak = 0
    }

    private func generateOptions(correct: Int) -> [Int] {
        var pool: Set<Int> = [correct]
        // Generate 3 distractors
        while pool.count < 4 {
            let offset = Int.random(in: 1...15)
            let sign: Int = Bool.random() ? 1 : -1
            let candidate = correct + (offset * sign)
            if candidate >= 0 && candidate != correct {
                pool.insert(candidate)
            }
        }
        // Shuffle
        return pool.shuffled()
    }

    private func unlockParentalAccess() {
        coordinator.store.updatePreferences {
            $0.isKidsModeActive = false
            $0.pedagogicalMode = "teacher"
        }
        isPresented = false
    }
}

// MARK: - Models

enum Operator: Sendable {
    case plus, minus, times

    var symbol: String {
        switch self {
        case .plus: return "+"
        case .minus: return "−"
        case .times: return "×"
        }
    }
}

struct Equation: Sendable {
    let first: Int
    let second: Int
    let third: Int
    let op1: Operator
    let op2: Operator

    var result: Int {
        let intermediate = evaluate(first, second, op1)
        return evaluate(intermediate, third, op2)
    }

    var displayText: String {
        "\(first) \(op1.symbol) \(second) \(op2.symbol) \(third)"
    }

    private func evaluate(_ a: Int, _ b: Int, _ op: Operator) -> Int {
        switch op {
        case .plus: return a + b
        case .minus: return a - b
        case .times: return a * b
        }
    }
}
