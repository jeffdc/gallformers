defmodule Gallformers.GuardrailsTest do
  # heartwood_guardrails' ratchets and hooks, as gallformers uses them
  # (docs/cleanup, step 11); heartwood tests the framework and the hooks.
  # DuplicateCode runs Credo, which toggles a global output switch: not async.
  use ExUnit.Case, async: false

  import Heartwood.Guardrails.Assertions

  test "no new copied code", do: assert_ratchet(Heartwood.Guardrails.DuplicateCode)
  test "replaced code is deleted", do: assert_no_outstanding_retirements()

  describe "the git hooks" do
    test "dev/githooks/ holds heartwood's shim, as of the pinned tag" do
      shim = Path.join(Mix.Project.deps_paths()[:heartwood_guardrails], "hooks/app-shim")

      for hook <- ["pre-commit", "pre-push"] do
        assert File.read!("dev/githooks/#{hook}") == File.read!(shim),
               "dev/githooks/#{hook} isn't heartwood's hooks/app-shim: copy it again (its CHANGELOG.md says when)."
      end
    end

    # With HEARTWOOD_PATH set, the hooks use that checkout instead.
    test "the hooks find the package: HEARTWOOD_HOME, when set, or the shim's default" do
      home =
        case Regex.run(~r/^HEARTWOOD_HOME=(\S+)$/m, File.read!("dev/guardrails/config.sh")) do
          [_, home] -> home
          nil -> "deps/heartwood_guardrails/guardrails"
        end

      if System.get_env("HEARTWOOD_PATH") == nil do
        assert Path.expand(home) == Path.expand(Mix.Project.deps_paths()[:heartwood_guardrails])
      end
    end
  end
end
