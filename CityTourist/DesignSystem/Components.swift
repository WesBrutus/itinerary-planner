import SwiftUI

// MARK: - Rating

/// "★ 4.87 (312)" — Airbnb sets the star solid black, never gold.
struct RatingLabel: View {
    let rating: Double
    var reviewCount: Int? = nil
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(size <= 12 ? .caption2 : .caption)
            Text(rating, format: .number.precision(.fractionLength(2)))
                .font(size <= 12 ? .caption.weight(.medium) : .subheadline.weight(.medium))
            if let reviewCount {
                Text("(\(reviewCount))")
                    .font(size <= 12 ? .caption : .subheadline)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
        .foregroundStyle(Palette.ink)
    }
}

// MARK: - Heart

struct HeartButton: View {
    let isSaved: Bool
    var size: CGFloat = 24
    let action: () -> Void

    @State private var bounce = false

    var body: some View {
        Button {
            action()
            bounce = true
        } label: {
            Image(systemName: isSaved ? "heart.fill" : "heart")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isSaved ? Brand.rausch : .white)
                // The dark outline is what keeps the white heart legible on any photo.
                .shadow(color: .black.opacity(isSaved ? 0 : 0.45), radius: 2, y: 1)
                .overlay {
                    if !isSaved {
                        Image(systemName: "heart")
                            .font(.system(size: size, weight: .medium))
                            .foregroundStyle(.black.opacity(0.28))
                    }
                }
                .symbolEffect(.bounce, value: bounce)
                .contentTransition(.symbolEffect(.replace))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "Remove from saved" : "Save")
    }
}

/// Circular glass action button over card photography (e.g. quick-add to trip).
struct PhotoActionButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = 15
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Palette.onPhotoInk)
                .frame(width: 34, height: 34)
                .background(Palette.onPhoto.opacity(0.92), in: Circle())
                .floatingShadow(y: 2, radius: 6, opacity: 0.2)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(L10n.text(title))
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background {
                    // Airbnb's CTA is a subtle left-to-right rausch→magenta ramp.
                    LinearGradient(
                        colors: [Brand.rausch, Brand.rauschDeep],
                        startPoint: .leading, endPoint: .trailing
                    )
                }
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous))
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(L10n.text(title))
            }
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .foregroundStyle(Palette.ink)
            .background(Palette.elevated)
            .overlay {
                RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                    .strokeBorder(Palette.ink, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Small black capsule used for "Map" and other floating affordances.
struct CapsuleActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(L10n.text(title)).font(.subheadline.weight(.semibold))
                Image(systemName: systemImage).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Palette.canvas)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Palette.ink, in: Capsule())
            .floatingShadow(y: 4, radius: 12, opacity: 0.28)
        }
        .buttonStyle(.plain)
    }
}

/// Circular white glass button that floats over photography (back, share, close).
struct GlassCircleButton: View {
    let systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .floatingShadow(y: 1, radius: 4, opacity: 0.18)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chips

struct Chip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.footnote.weight(.medium)) }
            Text(L10n.text(title)).font(.subheadline.weight(isSelected ? .semibold : .regular))
        }
        .foregroundStyle(isSelected ? Palette.canvas : Palette.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isSelected ? Palette.ink : Palette.elevated)
        .overlay {
            Capsule().strokeBorder(isSelected ? .clear : Palette.hairline, lineWidth: 1)
        }
        .clipShape(Capsule())
    }
}

// MARK: - Category rail
//
// The row of line icons under the search bar. Selection is marked by a black
// underline and full-opacity icon — no fill, no pill.
struct CategoryRail: View {
    @Binding var selection: PlaceCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 28) {
                item(nil, title: "All", symbol: "sparkles")
                ForEach(PlaceCategory.allCases) { category in
                    item(category, title: category.title, symbol: category.symbol)
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.top, 4)
        }
        .scrollClipDisabled()
    }

    private func item(_ category: PlaceCategory?, title: String, symbol: String) -> some View {
        let isSelected = selection == category
        return Button {
            withAnimation(.snappy(duration: 0.22)) { selection = category }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: isSelected ? .medium : .regular))
                Text(L10n.text(title))
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .fixedSize()
                Capsule()
                    .fill(isSelected ? Palette.ink : .clear)
                    .frame(height: 2)
            }
            .foregroundStyle(isSelected ? Palette.ink : Palette.inkMuted)
            .padding(.bottom, 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search pill

/// The floating capsule at the top of Explore. Left side switches cities or dates;
/// trailing button searches specific places in the current city.
struct SearchPill: View {
    let title: String
    let subtitle: String
    let action: () -> Void
    var onPlaceSearch: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Palette.ink)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(L10n.text(title))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Palette.inkMuted)
                        }
                        Text(L10n.text(subtitle))
                            .font(.caption)
                            .foregroundStyle(Palette.inkMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.vertical, 10)
                .padding(.leading, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onPlaceSearch {
                Button(action: onPlaceSearch) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.caption.weight(.semibold))
                        Text("Places")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(Palette.surface, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Palette.hairline, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .accessibilityLabel("Search places near \(title)")
                .accessibilityIdentifier("explorePlaceSearch")
            }
        }
        .background(Palette.elevated, in: Capsule())
        .overlay { Capsule().strokeBorder(Palette.hairline, lineWidth: 1) }
        .floatingShadow(y: 2, radius: 8, opacity: 0.10)
    }
}

// MARK: - Structure

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1 / UIScreen.main.scale)
    }
}

/// Section header with an optional trailing action, as used on detail screens.
struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.text(title)).sectionTitleStyle()
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .underline()
            }
        }
    }
}

/// Bottom bar pinned over content — hairline on top, material behind, safe-area aware.
struct StickyBottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            content
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 12)
                .padding(.bottom, 8)
        }
        .background(.bar)
    }
}

/// Empty-state block: glyph, headline, one line of guidance, one action.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.inkFaint)
                .padding(.bottom, 4)
            Text(L10n.text(title))
                .font(.title3.weight(.semibold))
                .tracking(-0.3)
                .foregroundStyle(Palette.ink)
            Text(L10n.text(message))
                .metaStyle()
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let actionTitle, let action {
                SecondaryButton(title: actionTitle, action: action)
                    .frame(maxWidth: 240)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metric.gutter)
    }
}

// MARK: - Avatars

struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 36

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Brand.rausch, Brand.rauschDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle()
            )
    }
}
