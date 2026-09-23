import Base
import ./check.bend as C
import ../src/core/gh.bend as G

# GitHub CLI accounts: remotes, gh auth status with several accounts (and
# gh before 2.40), the order accounts are tried in, and refusals.

def status() -> String:
  String.join(["github.com",
    "  ✓ Logged in to github.com account alice (keyring)",
    "  - Active account: true",
    "  - Git operations protocol: https",
    "  - Token: gho_************************************",
    "",
    "  ✓ Logged in to github.com account bob (keyring)",
    "  - Active account: false",
    "",
    "  X Failed to log in to github.com account carol (keyring)",
    "  - Active account: false",
    "",
    "  ✓ Logged in to github.com account acme-bot (GH_CONFIG_DIR)",
    "  - Active account: false",
    "ghe.example.com",
    "  ✓ Logged in to ghe.example.com account alice-corp (keyring)",
    "  - Active account: true"], "\n")

def accts(as: List<&2, G.GhAcct>) -> String:
  match as:
    case Nil{}:
      ""
    case G.GhAcct{u, a} <> t:
      u ++ Bool.pick(String, a, "*", "") ++ " " ++ accts(t)

def remote(+url: String) -> String:
  G.Gh.remote.host(G.Gh.remote(url)) ++ " " ++ G.Gh.remote.owner(G.Gh.remote(url))

def order(+saved: String, +owner: String) -> String:
  String.join(G.Gh.order(G.Gh.accounts(status(), "github.com"), saved, owner), ",")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("accounts", accts(G.Gh.accounts(status(), "github.com")), "alice* bob acme-bot ")
    C.Check.str("accounts other host", accts(G.Gh.accounts(status(), "ghe.example.com")), "alice-corp* ")
    C.Check.str("accounts old gh", accts(G.Gh.accounts("github.com\n  ✓ Logged in to github.com as alice (oauth_token)\n  ✓ Git operations for github.com configured to use https protocol.", "github.com")), "alice* ")
    C.Check.str("accounts none", accts(G.Gh.accounts("You are not logged into any GitHub hosts.", "github.com")), "")
    C.Check.str("remote https", remote("https://github.com/acme/widget.git"), "github.com acme")
    C.Check.str("remote https user", remote("https://bob@github.com/acme/widget"), "github.com acme")
    C.Check.str("remote scp", remote("git@github.com:acme/widget.git"), "github.com acme")
    C.Check.str("remote ssh port", remote("ssh://git@ghe.example.com:2222/team/widget.git"), "ghe.example.com team")
    C.Check.str("remote path", remote("/srv/git/widget.git"), " ")
    C.Check.str("remote file", remote("file:///srv/git/widget.git"), " ")
    C.Check.str("order active first", order("", "acme"), "alice,bob,acme-bot")
    C.Check.str("order owner first", order("", "bob"), "bob,alice,acme-bot")
    C.Check.str("order saved first", order("acme-bot", "bob"), "acme-bot,alice,bob")
    C.Check.str("order saved gone", order("carol", "bob"), "bob,alice,acme-bot")
    C.Check.str("refused 404", Bool.show(G.Gh.refused("GraphQL: Could not resolve to a Repository with the name 'acme/widget'. (repository)")), "True")
    C.Check.str("refused push", Bool.show(G.Gh.refused("remote: Permission to acme/widget.git denied to alice.\nfatal: unable to access 'https://github.com/acme/widget.git/': The requested URL returned error: 403")), "True")
    C.Check.str("not refused", Bool.show(G.Gh.refused("a pull request for branch \"x\" into branch \"main\" already exists")), "False")
    C.Check.str("token var", G.Gh.token_var("github.com") ++ " " ++ G.Gh.token_var("ghe.example.com"), "GH_TOKEN GH_ENTERPRISE_TOKEN")
