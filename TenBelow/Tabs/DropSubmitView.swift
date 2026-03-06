//
//  DropSubmitView.swift
//  TenBelow
//

import SwiftUI

struct DropSubmitView: View {
    @AppStorage("sellerSellerId") private var sellerId = ""
    @Environment(\.dismiss) private var dismiss

    @State private var submissions: SellerSubmissionsResponse?
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    // Form fields
    @State private var productName = ""
    @State private var priceString = ""
    @State private var selectedCategory: Category = .home
    @State private var material = ""
    @State private var durabilityNote = ""
    @State private var careWarning = ""
    @State private var shipsMinDays = 3
    @State private var shipsMaxDays = 7

    private var priceCents: Int {
        let dollars = Double(priceString) ?? 0
        return Int(dollars * 100)
    }

    private var priceValid: Bool { priceCents >= DropConstants.minPriceCents }
    private var slotsUsed: Int { submissions?.slotsUsed ?? 0 }
    private var slotsMax: Int { submissions?.slotsMax ?? DropConstants.maxSlotsPerSeller }
    private var slotsRemaining: Int { slotsMax - slotsUsed }
    private var isWindowOpen: Bool { submissions?.isActive ?? false }

    private var canSubmit: Bool {
        !productName.isEmpty && priceValid && slotsRemaining > 0 && isWindowOpen && !isSubmitting
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TBTheme.spacingXL) {

                windowStatusBanner

                slotCounter

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                if let msg = successMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(msg)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }

                if isWindowOpen && slotsRemaining > 0 {
                    submissionForm
                }

                mySubmissionsList
            }
            .padding()
        }
        .background(TBTheme.cloudWhite)
        .navigationTitle("Weekly Drop")
        .task { await loadSubmissions() }
    }

    // MARK: - Window status

    @ViewBuilder
    private var windowStatusBanner: some View {
        if let subs = submissions {
            HStack(spacing: 10) {
                Image(systemName: subs.isActive ? "flame.fill" : "clock")
                    .font(.title3)
                    .foregroundStyle(subs.isActive ? .orange : TBTheme.skyBlue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(subs.isActive ? "Drop Window Open" : "Drop Window Closed")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(subs.isActive ? .orange : .secondary)

                    if subs.isActive {
                        Text("Submit premium products (over $10) until Sunday midnight UTC")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let next = subs.nextDropAt {
                        Text("Next drop opens \(DropCountdown.timeLeft(until: next))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(TBTheme.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .fill(subs.isActive ? Color.orange.opacity(0.08) : TBTheme.subtleGray)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .strokeBorder(subs.isActive ? Color.orange.opacity(0.2) : TBTheme.skyBlue.opacity(0.15), lineWidth: 1)
            )
        }
    }

    // MARK: - Slot counter

    @ViewBuilder
    private var slotCounter: some View {
        HStack {
            Text("Slots Used")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                ForEach(0..<slotsMax, id: \.self) { i in
                    Circle()
                        .fill(i < slotsUsed ? TBTheme.accent : TBTheme.skyBlue.opacity(0.2))
                        .frame(width: 12, height: 12)
                }
            }
            Text("\(slotsUsed)/\(slotsMax)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TBTheme.deepSky)
        }
        .padding(TBTheme.spacingMD)
        .background(TBTheme.cardGradient)
        .cornerRadius(TBTheme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .strokeBorder(TBTheme.skyBlue.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Submission form

    @ViewBuilder
    private var submissionForm: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
            Text("New Drop Product")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(TBTheme.frostTitleGradient)

            TextField("Product name", text: $productName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("$")
                    .font(.headline)
                    .foregroundStyle(TBTheme.icyBlue)
                TextField("Price (e.g. 15.00)", text: $priceString)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
            }

            if !priceString.isEmpty && !priceValid {
                Text("Price must be over $10.00 for drop products")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Picker("Category", selection: $selectedCategory) {
                ForEach(Category.allCases) { cat in
                    Text(cat.rawValue).tag(cat)
                }
            }

            TextField("Material (e.g. PETG, Resin)", text: $material)
                .textFieldStyle(.roundedBorder)

            TextField("Durability note", text: $durabilityNote)
                .textFieldStyle(.roundedBorder)

            TextField("Care warning (optional)", text: $careWarning)
                .textFieldStyle(.roundedBorder)

            HStack {
                Stepper("Ships in \(shipsMinDays)–\(shipsMaxDays) days", value: $shipsMinDays, in: 1...14)
            }
            .font(.subheadline)

            Button {
                Task { await submitProduct() }
            } label: {
                if isSubmitting {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding()
                } else {
                    Text("Submit to Drop")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSubmit)
        }
    }

    // MARK: - My submissions list

    @ViewBuilder
    private var mySubmissionsList: some View {
        if let subs = submissions, !subs.products.isEmpty {
            VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                Text("Your Submissions This Week")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.icyBlue)

                ForEach(subs.products) { product in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.name)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(TBTheme.deepSky)
                            Text(Money.format(cents: product.priceCents))
                                .font(.tbPriceSmall)
                                .foregroundStyle(TBTheme.icyBlue)
                            Text(product.material)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isWindowOpen {
                            Button(role: .destructive) {
                                Task { await deleteProduct(product.id) }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(TBTheme.spacingMD)
                    .background(TBTheme.cardGradient)
                    .cornerRadius(TBTheme.radiusLG)
                    .overlay(
                        RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                            .strokeBorder(TBTheme.skyBlue.opacity(0.15), lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func loadSubmissions() async {
        guard !sellerId.isEmpty else { return }
        isLoading = true
        do {
            submissions = try await DropAPI.mySubmissions(sellerId: sellerId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func submitProduct() async {
        errorMessage = nil
        successMessage = nil
        isSubmitting = true

        let warnings = careWarning.isEmpty ? [] : [careWarning]

        let request = DropSubmissionRequest(
            sellerId: sellerId,
            name: productName,
            priceCents: priceCents,
            category: selectedCategory.rawValue,
            material: material.isEmpty ? "PLA+" : material,
            durabilityNote: durabilityNote,
            careWarnings: warnings,
            shipsInMinDays: shipsMinDays,
            shipsInMaxDays: shipsMaxDays
        )

        do {
            let product = try await DropAPI.submitProduct(request)
            successMessage = "\(product.name) added to this week's drop!"

            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif

            productName = ""
            priceString = ""
            material = ""
            durabilityNote = ""
            careWarning = ""

            await loadSubmissions()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }

    private func deleteProduct(_ productId: String) async {
        do {
            try await DropAPI.deleteSubmission(productId: productId)
            await loadSubmissions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        DropSubmitView()
    }
}
