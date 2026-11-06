# The test databases' names, one pair per checkout: in a git worktree
# (`.worktrees/<name>` or `.claude/worktrees/<name>`) they carry the worktree's name, so its tests never
# share a database with the main checkout's or another worktree's (a shared
# one sees the other's migrations, and concurrent runs lock each other). The
# main checkout and CI keep the plain names.
#
# Evaluates to a function: checkout root -> %{app: name, wcvp: name}. Read
# by config/test.exs and the Makefile (`make test-db`).
fn root ->
  suffix =
    case Regex.run(~r{/\.(?:claude/)?worktrees/([^/]+)}, root) do
      [_, name] ->
        "_" <> (name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_"))

      nil ->
        ""
    end

  %{app: "gallformers_test" <> suffix, wcvp: "wcvp_test" <> suffix}
end
