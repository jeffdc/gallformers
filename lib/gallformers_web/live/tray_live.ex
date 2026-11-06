defmodule GallformersWeb.TrayLive do
  @moduledoc """
  The curator's tray (design system matters bc0d and ec2c): one sticky
  LiveView in the root layout, on every page, public and admin, for
  curators only (`GallformersWeb.Live.UserAuth.curator/1`).

  While the curator's change set (`Gallformers.Curation`) holds items, the
  tray bar sits at the foot of the screen (`change_tray`). It keeps up
  with the set through PubSub, so an edit made on any page shows at once.
  Review and apply opens a dialog (`review_apply`): each item with the back
  end's flags, taken out singly, confirmed where it needs it, applied
  alone or all together; the evidence for the Fact items is asked once
  (why, observation links, a Source). Discard asks first.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Curation
  alias Gallformers.Sources
  alias GallformersWeb.Live.UserAuth

  @impl true
  def mount(_params, session, socket) do
    curator = UserAuth.curator(session["current_user"])
    if curator && connected?(socket), do: Curation.subscribe(curator)

    socket =
      socket
      |> assign(
        curator: curator,
        reviewing: false,
        discarding: false,
        confirmed: [],
        held: [],
        source_query: "",
        source_results: []
      )
      |> refresh()

    {:ok, socket, layout: false}
  end

  # The bar's summary; with Review open, the items, their flags and the
  # evidence too.
  defp refresh(%{assigns: %{curator: nil}} = socket),
    do: assign(socket, summary: nil, items: [], evidence: no_evidence(), source: nil)

  defp refresh(%{assigns: %{curator: curator}} = socket) do
    summary = Curation.summary(curator)
    socket = assign(socket, summary: summary)

    cond do
      summary.count == 0 ->
        assign(socket, reviewing: false, items: [], evidence: no_evidence(), source: nil)

      socket.assigns.reviewing ->
        set = Curation.open_set(curator)
        evidence = evidence(set && set.evidence)

        assign(socket,
          items: Enum.map(Curation.preview(curator), &item/1),
          evidence: evidence,
          source: source(evidence.source_id)
        )

      true ->
        socket
    end
  end

  defp item(entry) do
    %{
      id: entry.id,
      kind: entry.kind,
      text: "#{entry.subject_name}: #{entry.text}",
      flags: entry.flags,
      state: entry.state
    }
  end

  defp no_evidence, do: %{text: "", observations: [], source_id: nil}

  defp evidence(nil), do: no_evidence()

  defp evidence(evidence),
    do: %{
      text: evidence.text || "",
      observations: evidence.observations || [],
      source_id: evidence.source_id
    }

  defp source(nil), do: nil

  defp source(id) do
    case Sources.list_sources_by_id([id]) do
      [source] -> %{id: source.id, title: source.title}
      [] -> nil
    end
  end

  @impl true
  def handle_info({:change_set, _change}, socket), do: {:noreply, refresh(socket)}

  @impl true
  def handle_event(_event, _params, %{assigns: %{curator: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("tray_review", _params, socket),
    do: {:noreply, socket |> assign(reviewing: true, held: []) |> refresh()}

  def handle_event("close_review", _params, socket),
    do: {:noreply, assign(socket, reviewing: false)}

  def handle_event("remove_item", %{"id" => id}, socket) do
    Curation.remove_item(socket.assigns.curator, int(id))
    {:noreply, refresh(socket)}
  end

  def handle_event("toggle_confirm", %{"id" => id}, socket) do
    id = int(id)
    confirmed = socket.assigns.confirmed

    confirmed = if id in confirmed, do: List.delete(confirmed, id), else: [id | confirmed]
    {:noreply, assign(socket, confirmed: confirmed)}
  end

  def handle_event("apply_item", %{"id" => id}, socket) do
    %{curator: curator, confirmed: confirmed} = socket.assigns
    {:ok, result} = Curation.apply_item(curator, int(id), confirm: confirmed)
    {:noreply, applied(socket, result)}
  end

  def handle_event("apply_all", _params, socket) do
    %{curator: curator, confirmed: confirmed} = socket.assigns
    {:ok, result} = Curation.apply(curator, confirm: confirmed)
    {:noreply, applied(socket, result)}
  end

  def handle_event("set_evidence", %{"evidence" => params}, socket) do
    evidence = %{
      text: params["text"],
      observations: observations(params["observations"] || ""),
      source_id: socket.assigns.evidence.source_id
    }

    {:noreply, put_evidence(socket, evidence)}
  end

  def handle_event("search_evidence_source", %{"value" => query}, socket) do
    results =
      if String.length(String.trim(query)) >= 2,
        do:
          query
          |> Sources.search_sources()
          |> Enum.take(20)
          |> Enum.map(&%{id: &1.id, title: &1.title}),
        else: []

    {:noreply, assign(socket, source_query: query, source_results: results)}
  end

  def handle_event("select_evidence_source", %{"id" => id}, socket) do
    socket = assign(socket, source_query: "", source_results: [])
    {:noreply, put_evidence(socket, %{socket.assigns.evidence | source_id: int(id)})}
  end

  def handle_event("clear_evidence_source", _params, socket),
    do: {:noreply, put_evidence(socket, %{socket.assigns.evidence | source_id: nil})}

  def handle_event("tray_discard", _params, socket),
    do: {:noreply, assign(socket, discarding: true)}

  def handle_event("cancel_discard_tray", _params, socket),
    do: {:noreply, assign(socket, discarding: false)}

  def handle_event("confirm_discard_tray", _params, socket) do
    :ok = Curation.discard(socket.assigns.curator)
    {:noreply, socket |> assign(discarding: false, reviewing: false, confirmed: []) |> refresh()}
  end

  defp put_evidence(socket, evidence) do
    case Curation.set_evidence(socket.assigns.curator, evidence) do
      {:ok, _set} ->
        refresh(socket)

      {:error, :invalid_evidence} ->
        put_flash(
          socket,
          :error,
          "That evidence wasn't recognised: check the links and the Source."
        )
    end
  end

  defp applied(socket, %{held: held}) do
    socket |> assign(held: held) |> refresh()
  end

  # Observation links, separated by commas, spaces or new lines: iNaturalist
  # (…/observations/123) and BugGuide (…/node/view/123). Anything else is
  # ignored.
  defp observations(text) do
    text
    |> String.split(~r/[\s,]+/, trim: true)
    |> Enum.flat_map(fn link ->
      cond do
        id = capture(~r{inaturalist\.org/observations/(\d+)}, link) ->
          [%{provider: "inaturalist", id: id}]

        id = capture(~r{bugguide\.net/node/view/(\d+)}, link) ->
          [%{provider: "bugguide", id: id}]

        true ->
          []
      end
    end)
    |> Enum.uniq()
  end

  defp capture(regex, text) do
    case Regex.run(regex, text) do
      [_, id] -> id
      nil -> nil
    end
  end

  defp int(id) when is_integer(id), do: id
  defp int(id) when is_binary(id), do: String.to_integer(id)

  @impl true
  def render(assigns) do
    ~H"""
    <div id="tray">
      <.change_tray summary={@summary} />

      <.dialog
        :if={@reviewing}
        id="review-dialog"
        title="Review and apply"
        size={:lg}
        show
        on_cancel={JS.push("close_review")}
      >
        <.notice :if={@held != []} kind={:warn} title="Not applied" class="mb-block">
          <ul class="list-disc pl-5">
            <li :for={{_id, reason} <- @held}>{reason}</li>
          </ul>
        </.notice>
        <.review_apply
          id="review"
          items={@items}
          evidence={@evidence}
          confirmed={@confirmed}
          source={@source}
          source_query={@source_query}
          source_results={@source_results}
        />
      </.dialog>

      <.dialog
        :if={@discarding}
        id="discard-tray"
        title="Discard your changes?"
        size={:sm}
        show
        on_cancel={JS.push("cancel_discard_tray")}
      >
        Every change in your tray is dropped. Nothing has been applied, so nothing else changes.
        <:actions>
          <.button variant="ghost" phx-click="cancel_discard_tray">Keep them</.button>
          <.button variant="danger" phx-click="confirm_discard_tray">Discard changes</.button>
        </:actions>
      </.dialog>
    </div>
    """
  end
end
