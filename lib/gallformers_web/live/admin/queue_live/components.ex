defmodule GallformersWeb.Admin.QueueLive.Components do
  @moduledoc """
  Small pieces the review-queue pages share (matter a856, Task 3): the
  status of a package or batch as a badge.
  """
  use Phoenix.Component

  import GallformersWeb.CoreComponents, only: [badge: 1]

  @labels %{
    received: "Received",
    invalid: "Invalid",
    validated: "Validated",
    resolving: "Resolving",
    awaiting_review: "Awaiting review",
    approved: "Approved",
    denied: "Denied",
    pending: "Pending",
    blocked: "Blocked",
    ready: "Ready",
    applied: "Applied"
  }

  @doc "A package or batch status's label."
  @spec status_label(atom()) :: String.t()
  def status_label(status), do: Map.fetch!(@labels, status)

  @doc "The package statuses, as `{label, value}` select options."
  @spec package_status_options() :: [{String.t(), String.t()}]
  def package_status_options do
    for status <- [
          :received,
          :invalid,
          :validated,
          :resolving,
          :awaiting_review,
          :approved,
          :denied
        ],
        do: {status_label(status), Atom.to_string(status)}
  end

  @doc "A package's or batch's status as a badge."
  attr :status, :atom, required: true
  attr :id, :string, default: nil

  def status_badge(assigns) do
    ~H"""
    <span id={@id}>
      <.badge variant={variant(@status)}>{status_label(@status)}</.badge>
    </span>
    """
  end

  defp variant(status) when status in [:approved, :applied, :ready], do: "success"

  defp variant(status) when status in [:invalid, :denied, :blocked, :awaiting_review],
    do: "warning"

  defp variant(_status), do: "info"
end
