//
//  AppRoute.swift
//  ArigatoAI
//
//  Unified value-based navigation routes for the app's single
//  NavigationStack (rooted in ContentView). Every push on that stack is a
//  NavigationLink(value: AppRoute...) resolved by the ONE root
//  `.navigationDestination(for: AppRoute.self)`. There are deliberately NO
//  closure-form `NavigationLink { destination }` on this stack: mixing a
//  closure-form link (which re-evaluates constantly inside `.toolbar`)
//  with value-based links made the closure-form History link spuriously
//  re-fire on a value-based row tap, pushing a duplicate History list on
//  top of the correct MeetingDetailView.
//

import Foundation

/// Exhaustive set of value-based destinations on ``ContentView``'s root
/// `NavigationStack`. `Hashable` is synthesised because every associated
/// value is `Hashable`: the payload-free cases trivially so, and
/// ``MeetingSummary`` (declared only `Equatable` at its definition)
/// conforms via the explicit hand-written `hash(into:)` extension in
/// `MeetingListView.swift`. Registered exactly once at the stack root, so a
/// push of any case from any depth (History toolbar at root; gear + rows
/// from inside the pushed ``MeetingListView``) resolves against the same
/// declaration.
enum AppRoute: Hashable {
    /// Push the history list (``MeetingListView``).
    case history
    /// Push the settings surface (``SettingsView``).
    case settings
    /// Push the read-only detail for one past meeting (``MeetingDetailView``).
    case meetingDetail(MeetingSummary)
}
