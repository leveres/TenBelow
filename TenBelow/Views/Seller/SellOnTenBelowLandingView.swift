//
//  SellOnTenBelowLandingView.swift
//  TenBelow
//

import SwiftUI

/// Landing page for non-sellers: benefits and CTA to apply.
struct SellOnTenBelowLandingView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: TBTheme.spacingXXL) {
                headerSection
                benefitsSection
                ctaSection
            }
            .padding(TBTheme.spacingLG)
        }
        .background(TBTheme.cloudWhite)
        .navigationTitle("Sell on TenBelow")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var headerSection: some View {
        VStack(spacing: TBTheme.spacingMD) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 110, height: 110)

            Text("Reach buyers looking for unique 3D-printed products")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)
                .multilineTextAlignment(.center)
        }
        .padding(.top, TBTheme.spacingXL)
    }

    private var benefitsSection: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                benefitRow(icon: "dollarsign.circle.fill", title: "Everything $10 & under", detail: "Simple pricing that attracts buyers.")
                benefitRow(icon: "shippingbox.fill", title: "Flexible fulfillment", detail: "Ship from inventory or print to order for each sale.")
                benefitRow(icon: "chart.line.uptrend.xyaxis", title: "Weekly Drop exposure", detail: "Get featured in curated weekly drops.")
            }
        }
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: TBTheme.spacingMD) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.8))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(TBTheme.deepSky)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var ctaSection: some View {
        NavigationLink {
            SellerProfileView()
        } label: {
            Text("Apply to Sell")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [TBTheme.accent, TBTheme.deepSky],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
