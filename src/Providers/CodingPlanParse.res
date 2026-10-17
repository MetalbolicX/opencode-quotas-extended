// src/Providers/CodingPlanParse.res
// Parses coding-plan provider JSON responses into QuotaData.
// Facade — delegates to submodules while re-exporting helpers tests depend on.

type quotaData = Domain.quotaData
type windowType = Domain.windowType

// Re-exports from Shared (window mapping used by facade consumers + tests)
let windowMap = Shared.windowMap
let windowRank = Shared.windowRank

// Re-exports from ZaiParser (public API + helpers tests call directly)
let zaiWindow = ZaiParser.zaiWindow
let zaiSortRank = ZaiParser.zaiSortRank
let computeUsed = ZaiParser.computeUsed
let limitToQuota = ZaiParser.limitToQuota
let parseZaiLimits = ZaiParser.parseZaiLimits

// Re-exports from KimiParser (helpers tests call directly)
let kimiWindow = KimiParser.kimiWindow
let summaryToQuota = KimiParser.summaryToQuota
let limitRowToQuota = KimiParser.limitRowToQuota
let parseKimiUsages = KimiParser.parseKimiUsages

// Re-exports from GoParser
let parseGoUsage = GoParser.parseUsage
