# Cleanup App SwiftUI Clone Master Plan

## Goal

Clone the app shown in `/Users/sanjanabandara/Downloads/ScreenRecording_04-16-2026 22-37-17_1.MP4` as a high-fidelity SwiftUI app, including:

- onboarding flow
- permission prompts and gating
- paywall / free trial flow
- scanning dashboard
- utility modules
- dark visual system
- imagery-heavy cards
- animations and "cleaner utility" app vibe

This plan is based on a close review of the 63.65 second screen recording, sampled across the full journey and cross-checked on key frames.

## What The Video Actually Shows

### 1. Entry + Onboarding

Observed sequence:

- Welcome screen with large title: `Welcome to Cleanup`
- Two large icon blocks: `Photos` and `iCloud`
- red storage progress bar with usage text such as `209 of 255 GB used`
- privacy / terms copy near the bottom
- large blue `Get started` CTA
- iOS Photos full-access permission prompt
- onboarding card: `Delete Duplicate Photos`
- onboarding card: `Optimize iPhone Storage`
- onboarding card: `Clean Your Email Inbox`
- animated interstitial text: `Try 7 days` then `For free!`

### 2. Paywall

Observed paywall behavior:

- title: `Clean your Storage`
- subtitle: `Get rid of what you don't need`
- icon pair again: `Photos` and `iCloud`
- count badges over icons
- colored progress bar
- plan summary card for `Cleanup Pro`
- pricing copy: `Free for 7 days, then AED 39.99/week`
- `Free trial enabled` status card
- date / trial duration row
- primary CTA: `Try Free`
- `Restore Purchase` top left
- close `X` top right
- secure / legal text under CTA

### 3. Main App Dashboard

Observed home shell:

- title `Cleanup`
- small storage summary under title such as `5898 files • 231.8 GB of storage to clean up`
- blue scanning progress line under header
- `PRO` pill near top right
- settings gear top right
- content is an image-card grid of cleanup categories
- categories seen:
  - Similar
  - Duplicates
  - Similar Videos
  - Similar Screenshots
  - Screenshots
  - Videos
  - Other
- cards use big thumbnails and a blue badge CTA like `40 Photos`, `13 Videos`, `5816 Videos`
- dashboard scrolls vertically

### 4. Bottom Navigation

Observed tab bar items:

- Charging
- Secret Space
- Contacts
- Email Cleaner
- Compress

Important note:

- there is no obvious dedicated "Home" tab in the visible recording
- the `Cleanup` dashboard appears to be the default/root screen
- some feature screens return back to the dashboard

### 5. Charging Animation Module

Observed:

- title `Charging Animation`
- back button top left
- help / question icon top right
- tall poster-like preview tiles in 2-column grid
- visible examples:
  - neon battery
  - orange flower
  - electric lightning
  - stylized cat
- some tiles show a blue premium badge icon in the corner
- looks like a gallery rather than an actual editor in this clip

### 6. Secret Space Module

Observed:

- empty-state `Secret Library`
- cloud-style empty icon
- button `+ Add Files`
- modal / gate sheet:
  - `This is your Secret Library!`
  - privacy / protection pitch
  - `Create PIN`
  - `Maybe Later`
- another lock-state screen:
  - `You are your Secret Library!` or similar lock-state wording
  - button `Unlock Now`

Plan implication:

- this module needs at least 3 states:
  - empty library
  - create PIN gate
  - locked library

### 7. Contacts Module

Observed:

- title `Contacts`
- contact permission prompt
- branded illustration with robot-like mascot
- copy about needing access to scan contacts
- button `Go to Settings`

This looks permission-gated first, with no actual merge results shown in the clip.

### 8. Email Cleaner Module

Observed:

- title `Email Cleaner`
- same robot / mascot illustration language
- explanatory copy about category-based cleanup
- privacy policy link
- white Google sign-in button: `Sign in with Google`

No inbox results screen is shown. The video only reaches the auth entry screen.

### 9. Compress Module

Observed:

- title `Compress`
- storage summary text under title, e.g. `231.7 GB`
- sort dropdown / pill at top right: `Largest`
- dark info banner describing potential space savings
- value shown at right, e.g. `115.8 GB`
- masonry-like video grid with thumbnails
- small `iCloud` badges on thumbnails

This screen is clearly one of the more complete feature pages shown in the recording.

## Visual System To Clone

### Color Direction

Primary palette inferred from video:

- background: near-black navy
- panels: dark indigo / midnight blue
- CTA blue: bright iOS-like electric blue
- accent red: storage danger / badges
- accent green: free trial / good status
- accent cyan: premium / glow accents
- text: mostly white with soft gray secondary text

Suggested token set:

- `bgPrimary`: `#070B1B`
- `bgSecondary`: `#10162A`
- `cardBackground`: `#171D31`
- `ctaBlue`: `#138CFF`
- `accentRed`: `#F02147`
- `accentGreen`: `#39D353`
- `accentCyan`: `#53D6FF`
- `textPrimary`: `#FFFFFF`
- `textSecondary`: `#98A2B3`

### Typography

The app uses:

- large bold hero titles
- medium-weight body copy
- tight utility labels
- rounded App Store utility-app feel

SwiftUI recommendation:

- use SF Pro Display / SF Pro Text first for fidelity
- define a type ramp for:
  - hero title
  - section title
  - body copy
  - caption
  - badge text

### Shape Language

- oversized corner radius everywhere
- rounded buttons
- rounded cards
- pill badges
- soft blur modal surfaces

### Motion / Feel

- subtle glow around CTAs
- onboarding progress transitions
- interstitial text animation
- scanning bar animation
- soft floating / breathing effects around illustrations
- slight scale / fade on cards and sheets

## Product Map For The Clone

### Root Experience

1. Splash / launch state
2. Onboarding carousel
3. Permission prompts
4. Trial interstitial
5. Paywall
6. Dashboard scan screen
7. Feature tabs

### Core Screens To Build

1. Welcome onboarding screen
2. Photos permission screen / handoff
3. Delete duplicate photos onboarding screen
4. Optimize storage onboarding screen
5. Email cleanup onboarding screen
6. Trial interstitial animation screen
7. Paywall screen
8. Cleanup dashboard
9. Charging Animation gallery
10. Secret Space empty state
11. Secret Space PIN gate modal
12. Secret Space locked state
13. Contacts permission state
14. Email Cleaner auth state
15. Compress library screen
16. Settings screen

### Reusable UI Components

1. `PrimaryCTAButton`
2. `RoundedInfoCard`
3. `StorageUsageBar`
4. `DualSourceHeaderIcons`
5. `CountBadge`
6. `PremiumPill`
7. `CategoryTile`
8. `EmptyStatePanel`
9. `BlurredPermissionOverlay`
10. `BottomUtilityTabBar`
11. `InterstitialGlowText`
12. `PosterGridTile`

## SwiftUI App Architecture

### Recommended Structure

Use feature-first folders:

- `App`
- `Core`
- `DesignSystem`
- `Features/Onboarding`
- `Features/Paywall`
- `Features/Dashboard`
- `Features/Charging`
- `Features/SecretSpace`
- `Features/Contacts`
- `Features/EmailCleaner`
- `Features/Compress`
- `Features/Settings`
- `Services`
- `Models`
- `Assets`

### State Management

Recommended:

- SwiftUI + Observation framework (`@Observable`) if targeting modern iOS
- feature view models per module
- a single `AppRouter` / `AppFlowStore` for:
  - onboarding progression
  - permission completion
  - paywall presentation
  - selected tab

### Service Layer Needed

1. `PhotoLibraryService`
2. `ContactsService`
3. `EmailAuthService`
4. `CompressionEstimatorService`
5. `SecureVaultService`
6. `PurchaseService`
7. `SettingsService`

### Persistence

Use:

- `UserDefaults` for onboarding completion and selected options
- Keychain for PIN / secure vault metadata
- Core Data or SwiftData for scanned result caching if the clone needs persistence
- local mock JSON first, then real services second

## Feature-by-Feature Build Plan

### Phase 1. Visual Foundation

Build first:

- app theme tokens
- spacing scale
- typography scale
- reusable buttons / cards / badges
- bottom tab bar
- common illustrations / gradients / shadow presets

Deliverable:

- a `DesignSystem` package inside the app that makes every screen visually consistent

### Phase 2. Onboarding Flow

Build:

- screen 1: Welcome to Cleanup
- screen 2: Delete Duplicate Photos
- screen 3: Optimize iPhone Storage
- screen 4: Clean Your Email Inbox
- animated interstitial: Try 7 days / For free!

Requirements:

- progress indicator at top
- next/back progression logic
- permission handoff after first CTA
- identical spacing rhythm across all steps

Notes:

- first screen is more dense than the later onboarding slides
- later slides are more visual and simplified

### Phase 3. Permissions Layer

Implement:

- Photos access
- Contacts access
- Notifications access

Important:

- some prompts in the recording are native iOS alerts
- some are custom branded screens before or after the system prompt

Clone approach:

- custom pre-permission explainer screen
- then native `PHPhotoLibrary.requestAuthorization`
- `CNContactStore.requestAccess`
- `UNUserNotificationCenter.requestAuthorization`

### Phase 4. Paywall

Build a close visual clone:

- icon pair with red count badges
- dynamic storage bar
- feature list card
- trial summary card
- pricing details
- primary CTA
- restore purchase
- close action

Implementation detail:

- use StoreKit 2
- support products:
  - weekly trial product
  - restore purchases
- create a fallback local mock mode so UI can be built before StoreKit products exist

### Phase 5. Dashboard Scanner Home

Build:

- scrolling dashboard
- storage summary header
- scanning progress bar
- `PRO` pill
- settings button
- category cards with thumbnail previews and counts

The dashboard should support these states:

- initial scanning
- partial results streaming in
- fully loaded
- empty / permission denied

Strong recommendation:

- use local mocked scan output first
- simulate counts increasing over time to match the video's "scanning" vibe
- once visual parity is done, wire real photo analysis

### Phase 6. Real Cleanup Logic

For a real clone, implement actual scan engines:

1. Similar photos
   - use Vision feature prints or perceptual hashing
2. Duplicates
   - hash image data / asset metadata
3. Similar videos
   - cluster via duration + thumbnails + metadata
4. Screenshots
   - detect via `PHAssetMediaSubtype.photoScreenshot`
5. Videos
   - list by size
6. Other
   - uncategorized media bucket
7. iCloud state
   - derive from asset availability / cloud-backed metadata where possible

Important caution:

- exact iCloud cleanup behavior may not be fully reproducible from public APIs
- some values in the recording may be marketing-style derived numbers rather than exact device truth

### Phase 7. Charging Animation Module

Build:

- poster gallery grid
- premium lock / badge marker
- detail preview on tap
- optional "set charging animation" flow if you want feature completeness

Practical clone note:

- iOS does not allow arbitrary system charging-screen replacement in the way the UI implies
- the likely real implementation is:
  - video / live wallpaper style content
  - lock-screen instructions
  - shortcuts / automation instructions

So ship it as:

- gallery browser
- preview player
- save/share/apply instructions

### Phase 8. Secret Space Module

Build:

- empty library view
- add files CTA
- create PIN modal
- locked state
- unlock flow

Implementation details:

- photo / video import into app sandbox
- encrypt metadata or at least secure access path
- PIN stored via Keychain
- optional Face ID unlock

Required states:

- no PIN
- PIN creation
- locked
- unlocked empty
- unlocked with media

### Phase 9. Contacts Module

Build:

- permission state
- denied state
- scanning state
- duplicates list
- merge flow

Real logic:

- cluster contacts by name, phone, email similarity
- offer preview + merge confirmation

Recording note:

- only permission-denied / setup state is shown
- actual merge results need design continuation based on the same visual system

### Phase 10. Email Cleaner Module

Build:

- introduction screen
- Google sign-in
- mailbox category fetch
- cleanup selection flow
- delete/archive actions

Real implementation path:

- Sign in with Google
- Gmail API scopes
- fetch message categories / labels
- batch archive or trash

Security note:

- this is the riskiest integration in the app
- privacy messaging and consent flow must be explicit

### Phase 11. Compress Module

Build:

- video library screen
- sort controls
- estimated savings banner
- tiled video grid
- selection flow
- compression progress
- save/export result

Real implementation:

- local video compression via `AVAssetExportSession`
- estimated post-compress size preview
- iCloud tag display if asset is cloud-backed

### Phase 12. Settings / Utilities

Need a proper settings area even though only the gear is visible:

- subscription status
- restore purchases
- notification settings
- privacy policy
- terms
- contact support
- app version
- maybe "rate app"

## Asset Plan

### Assets You Must Recreate Or Source

1. App-style icons used in onboarding
2. Robot / mascot illustrations
3. Charging poster images / loops
4. Secret Space lock illustration
5. Email illustration
6. Dashboard sample thumbnails
7. Gradient / glow backgrounds

### Best Asset Strategy

- do not hardcode screenshots from the source app into production
- instead recreate the visual language with your own assets
- for prototype parity, use local placeholder media packs with similar color / composition

## Engineering Plan By Milestones

### Milestone 1. Clickable UI Clone

Goal:

- every visible screen exists
- flows navigate correctly
- no real scanning required yet

Includes:

- onboarding
- paywall
- dashboard
- tabs
- empty states
- compress UI

### Milestone 2. Local Mocked Data Clone

Goal:

- dashboard counts animate
- category tiles populate from seeded mock results
- feature screens look alive

Includes:

- fake scan engine
- fake storage math
- seeded thumbnails

### Milestone 3. Native Permissions + Real Device Data

Goal:

- photo permissions real
- contacts permissions real
- notification permissions real
- actual photo / video asset scanning

### Milestone 4. Monetization + Secure Features

Goal:

- StoreKit 2 paywall
- PIN lock
- Face ID
- restore purchase

### Milestone 5. Advanced Integrations

Goal:

- Gmail integration
- real compression workflow
- contact merge
- export / delete flows

## Recommended SwiftUI Technical Choices

### Navigation

- `NavigationStack` for module drill-down
- custom root shell for dashboard + tabs
- full-screen covers for:
  - paywall
  - onboarding entry
  - modal gates

### Layout

- use `ScrollView` + `LazyVGrid`
- use geometry-aware cards for poster layouts
- create a shared `ScreenContainer` for consistent padding and dark background

### Animation

- `matchedGeometryEffect` for some onboarding or card transitions if helpful
- `PhaseAnimator` or `symbolEffect` only where it helps
- scanning bar as repeating progress animation
- interstitial text via opacity + scale sequencing

### Images

- `PhotosPicker` / PhotoKit for media
- local caching for generated thumbnails
- async thumbnail loading service

## Risks And Non-Obvious Constraints

### Things You Can Clone Faithfully

- UI layout
- dark styling
- onboarding
- paywall
- dashboard card system
- compress library
- permission flows
- secret vault flow

### Things That Need Adaptation

1. Charging animation
   - iOS restrictions mean this likely cannot behave exactly as implied
2. Email cleanup
   - requires real Google auth and Gmail permissions
3. Exact storage statistics
   - some numbers may be marketing-derived, not direct iOS system numbers
4. iCloud cleanup semantics
   - limited by public APIs

## Build Order I Recommend

1. Design system
2. Onboarding
3. Paywall
4. Dashboard shell
5. Mock scan engine
6. Charging gallery
7. Secret Space states
8. Contacts permission flow
9. Email sign-in screen
10. Compress screen
11. Real photo scanning
12. Real subscriptions
13. Secure vault
14. Contacts merge
15. Gmail cleanup
16. Compression export

## Acceptance Checklist

The clone is "end to end" only when all of these are true:

- onboarding matches the video flow
- paywall is fully functional with StoreKit 2
- dashboard animates and renders real or mocked scan results
- all five utility tabs exist and are navigable
- Secret Space supports PIN creation and unlock
- Contacts flow handles denied and granted permissions
- Email Cleaner supports Google auth entry
- Compress supports selection and export
- settings and legal surfaces are complete
- visual polish matches the dark neon utility-app vibe

## What Is Still Not Fully Visible In The Video

These areas need product decisions because the recording does not fully expose them:

- settings screen content
- detailed duplicate review screens
- similar photo batch review workflow
- delete confirmation flows
- actual contact merge UI
- post-Google-sign-in inbox management screens
- compression progress and output confirmation screens
- secret library after media import

For those, the best path is:

- preserve the exact visual language already seen
- keep the information density consistent
- design the missing screens as a natural continuation of the shown app

## Final Recommendation

Do this as a two-track project:

### Track A. Pixel Clone

Focus on:

- visual parity
- flow parity
- animation parity
- navigation parity

### Track B. Functional Clone

Focus on:

- real permissions
- photo analysis
- compression
- contacts logic
- vault security
- Gmail integration
- subscriptions

If you try to do both at once, progress will slow down badly. Build the pixel-perfect shell first, then replace mocked modules one by one with real services.
