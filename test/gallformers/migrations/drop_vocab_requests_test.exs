defmodule Gallformers.Migrations.DropVocabRequestsTest do
  @moduledoc """
  The unused `vocab_requests` table (6611's vocabulary backlog, replaced by
  the superadmin vocabulary page, `d213`; matter `f14c`, Housekeeping) is
  dropped, with its audit trigger. Its replay kind stays: old entries are
  kept and skipped.
  """
  use Gallformers.DataCase, async: true

  test "the table is gone" do
    assert %{rows: [[nil]]} = Repo.query!("SELECT to_regclass('public.vocab_requests')")
  end

  test "the audit trail no longer tracks it" do
    assert %{rows: []} =
             Repo.query!(
               "SELECT 1 FROM carbonite_default.triggers WHERE table_name = 'vocab_requests'"
             )
  end
end
