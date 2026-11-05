defmodule GallformersWeb.Admin.Review.Section do
  @moduledoc """
  A section of one Source's review page: the questions of one kind
  (`GallformersWeb.Admin.Review.Questions`), with its title and
  explanation in the curator's words, whether its open questions hold
  approval, the badge saying so (`holds`) and what leaving one open means
  (`leave`).
  """

  @enforce_keys [:id, :title, :explanation, :holds_approval, :holds, :leave]
  defstruct [:id, :title, :explanation, :holds_approval, :holds, :leave]

  @type t :: %__MODULE__{
          id: atom(),
          title: String.t(),
          explanation: String.t(),
          holds_approval: boolean(),
          holds: String.t(),
          leave: String.t()
        }
end
