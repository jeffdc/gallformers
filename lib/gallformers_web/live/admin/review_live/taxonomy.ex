defmodule GallformersWeb.Admin.ReviewLive.Taxonomy do
  @moduledoc """
  The taxonomy queue (`/admin/review/taxonomy`, matter `f923` Task 6): the
  Sources' taxonomic statements (placements, names, synonymies, splits,
  common names) newer than what the tree follows, for a curator to accept
  or decline, across Sources (`Gallformers.Import.TaxonomyQueue`). They come
  after a Source's approval and hold none. The Sources list leads here
  while any is open, and a Source's overview links to its own
  (`?source=<id>`).

  One section per Source, the newest first, its questions in the rows a
  Source's page has (`GallformersWeb.Admin.ReviewLive.ItemRow`): Accept
  (recommended) makes the tree follow the statement; Decline asks for the
  reason once chosen. A refusal from the tree shows its reason in the row.
  Beside them, the split questions of a split the Source made
  (`Gallformers.Import.SplitQuestions`, `f923` "Splits"): for each Gall on
  the split taxon its own statements don't settle, which taxon induces it
  now (each daughter, or not known yet; a daughter its Galls share a Host
  with marked recommended).
  "Accept the rest of this paper" first shows what it would do to the tree
  (`Gallformers.Import.preview_accept_rest/2`: moves, renames, merges,
  Galls whose names change, splits and the Galls they ask about), then
  accepts the paper's open questions on confirmation; declined ones stay
  declined. After each decision the page loads again; "Show decided" lists
  the decided ones too.
  """
  use GallformersWeb, :live_view

  import GallformersWeb.ReviewComponents

  alias Gallformers.Import
  alias GallformersWeb.Admin.ReviewLive.ItemRow
  alias GallformersWeb.Admin.ReviewLive.Loader

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Taxonomy questions",
       show_decided: false,
       closed: MapSet.new(),
       preview: nil,
       source_id: nil
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    source_id =
      case Integer.parse(params["source"] || "") do
        {id, ""} -> id
        _ -> nil
      end

    {:noreply, socket |> assign(source_id: source_id, preview: nil) |> load()}
  end

  @impl true
  def handle_event("show_decided", _params, socket),
    do: {:noreply, socket |> assign(show_decided: not socket.assigns.show_decided) |> load()}

  def handle_event("toggle_section", %{"section" => section}, socket) do
    closed = socket.assigns.closed

    closed =
      if MapSet.member?(closed, section),
        do: MapSet.delete(closed, section),
        else: MapSet.put(closed, section)

    {:noreply, assign(socket, closed: closed)}
  end

  def handle_event("preview_rest", %{"source" => source}, socket) do
    source_id = String.to_integer(source)

    preview =
      case Import.preview_accept_rest(source_id, socket.assigns.actor) do
        {:ok, preview} -> preview
        {:error, reason} -> %{refused: {nil, reason}, items: []}
      end

    {:noreply, assign(socket, preview: {source_id, preview})}
  end

  def handle_event("cancel_rest", _params, socket), do: {:noreply, assign(socket, preview: nil)}

  def handle_event("accept_rest", %{"source" => source}, socket) do
    source_id = String.to_integer(source)

    case Import.accept_rest(socket.assigns.actor, source_id) do
      {:ok, %{accepted: accepted}} ->
        n = length(accepted)

        {:noreply,
         socket
         |> assign(preview: nil)
         |> put_flash(:info, "Accepted #{n} #{if n == 1, do: "statement", else: "statements"}.")
         |> load()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(preview: nil)
         |> put_flash(:error, Import.taxonomy_refusal(reason))
         |> load()}
    end
  end

  @impl true
  def handle_info({ItemRow, {:decided, _item}}, socket),
    do:
      {:noreply,
       socket |> assign(preview: nil) |> put_flash(:info, "Decision recorded.") |> load()}

  def handle_info({ItemRow, {:undone, _item}}, socket),
    do:
      {:noreply, socket |> assign(preview: nil) |> put_flash(:info, "Decision undone.") |> load()}

  def handle_info({ItemRow, {:proposal, _item}}, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    status = if socket.assigns.show_decided, do: :all, else: :open
    opts = [status: status] ++ if(id = socket.assigns.source_id, do: [source_id: id], else: [])
    assign(socket, groups: Loader.taxonomy(opts), definitions: Loader.definitions())
  end

  defp count_text(0), do: "· all decided"
  defp count_text(open), do: "· #{open} to decide"

  # The preview's lines, by what they are about.
  defp preview_lines(preview) do
    [
      {"Moves", for(m <- preview.moves, do: "#{m.name}: from #{m.from} to #{m.to}")},
      {"Renames", for(r <- preview.renames, do: "#{r.from} becomes #{r.to}")},
      {"Merges",
       for(m <- preview.merges, do: "#{m.name} merged into #{m.into || "another taxon"}")},
      {"Rank and authorship", for(d <- preview.details, do: "#{d.name}: #{d.text}")},
      {"Common names", for(c <- preview.common_names, do: common_name_line(c))},
      {"Galls renamed (proposed)", for(g <- preview.galls, do: gall_line(g))},
      {"Splits", for(s <- preview.splits, do: split_line(s))}
    ]
    |> Enum.reject(fn {_title, lines} -> lines == [] end)
  end

  defp common_name_line(%{name: name, added: added, removed: removed}) do
    parts =
      Enum.map(added, &"adds “#{&1}”") ++ Enum.map(removed, &"drops “#{&1}”")

    "#{name}: #{Enum.join(parts, ", ")}"
  end

  defp gall_line(%{from: from, to: to, collision: true}),
    do: "#{from} → #{to} (already another Gall's name: flagged)"

  defp gall_line(%{from: from, to: to}), do: "#{from} → #{to}"

  defp split_line(%{name: name, into: into, galls: galls}) do
    "#{name} into #{Enum.join(into, ", ")}: #{galls} #{if galls == 1, do: "Gall asks", else: "Galls ask"} which taxon induces it"
  end

  defp previewing(nil, _source_id), do: nil
  defp previewing({source_id, preview}, source_id), do: preview
  defp previewing(_preview, _source_id), do: nil

  @impl true
  def render(assigns) do
    open = assigns.groups |> Enum.map(& &1.open) |> Enum.sum()
    assigns = assign(assigns, open: open)

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-block">
        <.page_header>
          <:crumb navigate={~p"/admin/review"}>Sources to review</:crumb>
          <:title>Taxonomy questions</:title>
          <:description>
            A newer paper's taxonomic statement counts only once you accept it; the tree then
            follows it. Declining keeps the tree on the paper it follows now, with your reason.
            Once a split is accepted, each Gall on the split taxon that the paper doesn't settle
            asks which taxon induces it now. These come after a Source's approval, so nothing
            here holds one.
          </:description>
        </.page_header>

        <div id="taxonomy-head" class="flex flex-wrap items-center gap-2">
          <span id="progress" class="text-ui">{@open} to decide</span>
          <.link :if={@source_id} navigate={~p"/admin/review/taxonomy"} class="text-meta">
            Show every Source's
          </.link>
          <span class="flex-1"></span>
          <.button
            id="show-decided"
            phx-click="show_decided"
            size="sm"
            variant={if @show_decided, do: "primary", else: "secondary"}
          >
            Show decided
          </.button>
        </div>

        <div id="review-sections">
          <.empty_state :if={@groups == []} title="No taxonomy question is waiting." />
          <.review_section
            :for={g <- @groups}
            id={"section-source-#{g.source_id}"}
            section={"source-#{g.source_id}"}
            title={g.name}
            count={count_text(g.open)}
            explanation={g.summary && g.summary.title}
            holds="Doesn't hold approval"
            holds_approval={false}
            done={g.open == 0}
            closed={MapSet.member?(@closed, "source-#{g.source_id}")}
            on_toggle="toggle_section"
            layout={:question}
          >
            <:actions :if={g.acceptance_open > 0}>
              <.button
                id={"accept-rest-#{g.source_id}"}
                phx-click="preview_rest"
                phx-value-source={g.source_id}
                size="sm"
                variant="secondary"
              >
                Accept the rest of this paper ({g.acceptance_open})
              </.button>
            </:actions>
            <:confirm :for={preview <- List.wrap(previewing(@preview, g.source_id))}>
              <.notice
                :if={preview.refused}
                id={"accept-rest-preview-#{g.source_id}"}
                kind={:danger}
                title="The rest of this paper can't be accepted as it stands"
              >
                {Import.taxonomy_refusal(preview.refused)} Decide that statement on its own first.
                <:action>
                  <.button phx-click="cancel_rest" size="sm" variant="secondary">Close</.button>
                </:action>
              </.notice>
              <.notice
                :if={!preview.refused}
                id={"accept-rest-preview-#{g.source_id}"}
                kind={:warn}
                title={"Accepting #{length(preview.items)} #{if length(preview.items) == 1, do: "statement", else: "statements"} of #{g.name} does this to the tree"}
              >
                <p :if={preview_lines(preview) == []} class="text-meta">
                  Nothing in the tree changes: it follows these already.
                </p>
                <div :for={{title, lines} <- preview_lines(preview)} class="mt-1">
                  <p class="text-meta font-semibold">{title}</p>
                  <ul class="text-meta">
                    <li :for={line <- lines}>{line}</li>
                  </ul>
                </div>
                <:action>
                  <.button
                    id={"accept-rest-confirm-#{g.source_id}"}
                    phx-click="accept_rest"
                    phx-value-source={g.source_id}
                    size="sm"
                    variant="primary"
                  >
                    Accept {length(preview.items)}
                  </.button>
                  <.button phx-click="cancel_rest" size="sm" variant="secondary">Cancel</.button>
                </:action>
              </.notice>
            </:confirm>
            <.live_component
              :for={entry <- g.entries}
              module={ItemRow}
              id={"item-row-#{entry.item.id}"}
              entry={entry}
              actor={@actor}
              definitions={@definitions}
              source_name={g.name}
            />
          </.review_section>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
