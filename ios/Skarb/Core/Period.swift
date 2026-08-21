import Foundation

/// The windows a report can be read over. The raw values are the API's; the labels are ours.
nonisolated enum PeriodKey: String, Codable, CaseIterable, Sendable {
    case month
    case last
    case threeMonths = "3m"
    case sixMonths = "6m"
    case ytd

    /// The pill's label — short, because five of them share one row on a phone.
    var short: String {
        switch self {
        case .month: "This month"
        case .last: "Last month"
        case .threeMonths: "3M"
        case .sixMonths: "6M"
        case .ytd: "YTD"
        }
    }

    /// How a window names itself where its dates will not fit — inside the donut, mostly.
    var name: String {
        switch self {
        case .month: "This month"
        case .last: "Last month"
        case .threeMonths: "Last 3 months"
        case .sixMonths: "Last 6 months"
        case .ytd: "Year to date"
        }
    }

    /// The same window worked into a sentence: "nothing spent this month".
    var phrase: String {
        switch self {
        case .month: "this month"
        case .last: "last month"
        case .threeMonths: "over the last 3 months"
        case .sixMonths: "over the last 6 months"
        case .ytd: "this year so far"
        }
    }

    /// What a window is measured against. The server compares like with like — three weeks of
    /// August against the first three weeks of July, never against the whole of it — and this
    /// says so, because a percentage that quietly compares 21 days to 31 reads as a collapse
    /// in spending every month.
    var comparison: String {
        switch self {
        case .month: "on the same days last month"
        case .last: "on the month before"
        case .threeMonths: "on the previous 3 months"
        case .sixMonths: "on the previous 6 months"
        case .ytd: "on the same stretch last year"
        }
    }
}
