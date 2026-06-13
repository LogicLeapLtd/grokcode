import Foundation

/// GrokCode's own curated plugin marketplace — the "Discover" tab. These are
/// recommended MCP servers users can add, distinct from plugins imported from
/// other coding agents (grok/Claude/Codex/Cursor), which live on the Import tab.
enum MarketplaceCatalog {
    /// Curated entries. `sourceTool == .builtin` marks them as GrokCode's catalogue.
    static let plugins: [Plugin] = [
        make("context7", "Context7", "book.closed",
             "Up-to-date documentation for any library, injected straight into context.",
             cmd: "npx", args: ["-y", "@upstash/context7-mcp"]),
        make("github", "GitHub", "chevron.left.forwardslash.chevron.right",
             "Browse repos, manage issues and pull requests.",
             cmd: "npx", args: ["-y", "@modelcontextprotocol/server-github"]),
        make("filesystem", "Filesystem", "folder",
             "Read and write local files within an allowed directory.",
             cmd: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem"]),
        make("playwright", "Playwright", "cursorarrow.rays",
             "Drive a real Chrome browser for testing and scraping.",
             cmd: "npx", args: ["-y", "@playwright/mcp@latest"]),
        make("supabase", "Supabase", "cylinder.split.1x2",
             "Query and manage your Supabase Postgres database.",
             cmd: "npx", args: ["-y", "@supabase/mcp-server-supabase@latest"]),
        make("postgres", "PostgreSQL", "cylinder",
             "Run read-only SQL against any Postgres connection.",
             cmd: "npx", args: ["-y", "@modelcontextprotocol/server-postgres"]),
        make("sentry", "Sentry", "exclamationmark.triangle",
             "Inspect errors, issues and performance from Sentry.",
             url: "https://mcp.sentry.dev/mcp"),
        make("linear", "Linear", "checklist",
             "Create, search and update Linear issues.",
             url: "https://mcp.linear.app/sse"),
        make("notion", "Notion", "doc.richtext",
             "Search and edit pages across your Notion workspace.",
             cmd: "npx", args: ["-y", "@notionhq/notion-mcp-server"]),
        make("slack", "Slack", "message",
             "Read channels and post messages to Slack.",
             cmd: "npx", args: ["-y", "@modelcontextprotocol/server-slack"]),
        make("brave-search", "Brave Search", "magnifyingglass",
             "Live web search results via the Brave API.",
             cmd: "npx", args: ["-y", "@modelcontextprotocol/server-brave-search"]),
        make("stripe", "Stripe", "creditcard",
             "Look up customers, payments and invoices in Stripe.",
             cmd: "npx", args: ["-y", "@stripe/mcp"]),
    ]

    private static func make(_ id: String, _ name: String, _ icon: String, _ detail: String,
                             cmd: String? = nil, args: [String] = [], url: String? = nil) -> Plugin {
        Plugin(
            id: "marketplace:\(id)",
            name: name,
            kind: .mcpServer,
            sourceTool: .builtin,
            detail: detail,
            iconSystemName: icon,
            command: cmd,
            url: url,
            args: args
        )
    }
}
