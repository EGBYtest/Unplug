/// Which direction of a settings change is the one that needs a challenge.
///
/// The rule is the same one the in-app tab blockers and the two interstitials
/// already follow, applied to numbers instead of switches: **the challenge is
/// on the direction that makes the app more permissive, and never on the
/// direction that makes it stricter.** Charging a price for tightening means
/// the user cannot arm their own guard without permission, which is the same
/// thing as not letting them arm it at all.
///
/// The two shapes exist because a setting can be either a budget or a cost,
/// and which end of the scale is permissive depends on which:
///
///   * a **budget** — a daily limit, the minutes earned per wait. More is
///     more permissive, so raising it asks and lowering it is free.
///   * a **cost** — the wait itself. The user pays it to earn a reward, so
///     less is more permissive: a shorter wait buys the same reward for less
///     effort, and that is the direction that asks.
///
/// Everything here is a pure function of the old and new value so the whole
/// table can be tested directly. Gating a setting is the one place where being
/// wrong is the whole bug: a table tested here is worth more than a picker
/// dragged around in a widget test, because the picker mechanics can fail
/// either way silently while this cannot.
library;

/// True when moving a *budget* setting from [from] to [to] loosens it.
///
/// Equal values are not a loosening, and neither is a smaller one.
bool loosensBudget(num from, num to) => to > from;

/// True when moving a *cost* setting from [from] to [to] loosens it.
///
/// Equal values are not a loosening, and neither is a larger one.
bool loosensCost(num from, num to) => to < from;
