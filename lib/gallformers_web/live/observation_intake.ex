defmodule GallformersWeb.ObservationIntake do
  @moduledoc """
  Add from observation (matter `ec2c`): a curator gives one iNaturalist
  observation; `Gallformers.Curation.from_observation/3` reads it into
  proposals (the recorded occurrence, dated as seen; the Hosts its "Host
  Plant ID" field and description name), each ticked as proposed; the
  curator confirms them into the tray (`Gallformers.Curation.add_item/2`),
  each with the observation as its evidence
  (`Gallformers.Curation.set_item_evidence/3`). Its photos are offered
  through the iNaturalist image import
  (`GallformersWeb.Admin.InatImportComponent`, given the observation
  already read); photos save at once, not through the tray.

  On the Gall page in Edit mode the Gall is given (`gall`); from the
  command palette (`/admin/observation`) it is chosen: among the Galls the
  observation's taxon induces (one is chosen when it is the only one, or
  when the observation's "Gallformers Code" names it), or any Gall by
  name.

  Assigns: `id`, `curator` (an `%Actor{}`), `gall` (`%{id, name}` or nil).
  """
  use GallformersWeb, :live_component

  alias Gallformers.Catalog
  alias Gallformers.Curation
  alias GallformersWeb.Admin.InatImportComponent

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       url: "",
       proposal: nil,
       error: nil,
       chosen: nil,
       gall_query: "",
       gall_results: [],
       selected: MapSet.new(),
       added: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     assign(socket,
       id: assigns.id,
       curator: assigns.curator,
       gall: Map.get(assigns, :gall)
     )}
  end

  @impl true
  def handle_event("read", %{"url" => url}, socket) do
    %{curator: curator, gall: gall} = socket.assigns

    case Curation.from_observation(curator, String.trim(url), gall && gall.id) do
      {:ok, proposal} ->
        {:noreply, socket |> assign(url: url, error: nil, added: nil) |> propose(proposal)}

      {:error, reason} ->
        {:noreply, assign(socket, url: url, error: error_text(reason), proposal: nil)}
    end
  end

  def handle_event("toggle_item", %{"index" => index}, socket) do
    index = String.to_integer(index)

    selected =
      if MapSet.member?(socket.assigns.selected, index),
        do: MapSet.delete(socket.assigns.selected, index),
        else: MapSet.put(socket.assigns.selected, index)

    {:noreply, assign(socket, selected: selected)}
  end

  def handle_event("choose_gall", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.proposal.gall.candidates, &("#{&1.id}" == id)) do
      nil -> {:noreply, socket}
      gall -> {:noreply, choose(socket, %{id: gall.id, name: gall.name})}
    end
  end

  def handle_event("search_gall", %{"value" => query}, socket) do
    results =
      if String.length(String.trim(query)) >= 2,
        do: query |> Catalog.search_galls() |> Enum.take(20),
        else: []

    {:noreply, assign(socket, gall_query: query, gall_results: results)}
  end

  def handle_event("select_gall", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.gall_results, &("#{&1.id}" == id)) do
      nil -> {:noreply, socket}
      gall -> {:noreply, choose(socket, %{id: gall.id, name: gall.name})}
    end
  end

  def handle_event("clear_gall", _params, socket),
    do: {:noreply, assign(socket, chosen: nil, gall_query: "", gall_results: [])}

  def handle_event("add", _params, %{assigns: %{chosen: nil}} = socket), do: {:noreply, socket}

  def handle_event("add", _params, socket) do
    %{proposal: proposal, selected: selected, chosen: gall, curator: curator} = socket.assigns

    results =
      for {item, index} <- Enum.with_index(proposal.items), MapSet.member?(selected, index) do
        spec = %{item.spec | gall_id: gall.id}

        with {:ok, added} <- Curation.add_item(curator, spec),
             {:ok, _} <- Curation.set_item_evidence(curator, added.id, proposal.evidence) do
          :ok
        else
          {:error, reason} -> {:error, item.text, reason}
        end
      end

    errors = for {:error, text, reason} <- results, do: "#{text}: #{refusal(reason)}"

    {:noreply,
     assign(socket,
       added: %{count: Enum.count(results, &(&1 == :ok)), errors: errors},
       selected: MapSet.new()
     )}
  end

  defp propose(socket, proposal) do
    selected =
      for {item, index} <- Enum.with_index(proposal.items),
          item.selected,
          into: MapSet.new(),
          do: index

    chosen =
      cond do
        socket.assigns.gall -> socket.assigns.gall
        id = proposal.gall.gall_id -> %{id: id, name: candidate_name(proposal, id)}
        true -> nil
      end

    socket
    |> assign(proposal: proposal, selected: selected, chosen: nil)
    |> then(&if(chosen, do: choose(&1, chosen), else: &1))
  end

  defp candidate_name(proposal, id) do
    Enum.find_value(proposal.gall.candidates, "Gall #{id}", &(&1.id == id && &1.name))
  end

  # The Gall the items are about; its photos are offered for import.
  defp choose(socket, gall) do
    send_update(InatImportComponent,
      id: "#{socket.assigns.id}-photos",
      fetch_result: {:ok, socket.assigns.proposal.inat_observation}
    )

    assign(socket, chosen: gall, gall_query: "", gall_results: [])
  end

  defp error_text(:invalid_input),
    do: "That isn't an iNaturalist observation: give its link or its number."

  defp error_text(:not_found), do: "iNaturalist has no such observation."

  defp error_text(:unavailable),
    do: "iNaturalist couldn't be reached or answered with an error. Try again in a moment."

  defp error_text(:no_such_gall), do: "This Gall is gone: another curator deleted or merged it."

  defp refusal(:waiting), do: "already waiting to apply"
  defp refusal(:no_such_gall), do: "no such Gall"
  defp refusal(:no_such_place), do: "no such place"
  defp refusal(:no_such_taxon), do: "that plant isn't in Gallformers"
  defp refusal(reason), do: to_string(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col gap-block">
      <form
        id={"#{@id}-read"}
        phx-submit="read"
        phx-target={@myself}
        class="flex flex-wrap items-end gap-2"
      >
        <.field label="iNaturalist observation" for={"#{@id}-url"} class="min-w-0 flex-1">
          <input
            type="text"
            id={"#{@id}-url"}
            name="url"
            value={@url}
            placeholder="Its link or its number"
            autocomplete="off"
            class="gf-input"
          />
        </.field>
        <.button
          type="submit"
          variant={if @proposal, do: "secondary", else: "primary"}
          phx-disable-with="Reading…"
        >
          Read observation
        </.button>
      </form>

      <.notice :if={@error} kind={:danger}>{@error}</.notice>

      <div :if={@proposal} class="flex flex-col gap-block">
        <.fact_list layout={:inline} missing_label={nil}>
          <:item label="Observation">
            <a href={@proposal.observation.url} target="_blank" rel="noopener noreferrer">
              #{@proposal.observation.id} ↗
            </a>
          </:item>
          <:item label="Identified as" value={@proposal.observation.taxon_name}>
            <.taxon_name name={@proposal.observation.taxon_name} />
          </:item>
          <:item label="Seen" value={@proposal.observation.observed_on}>
            {@proposal.observation.observed_on}
          </:item>
          <:item label="Where" value={@proposal.observation.place_guess}>
            {@proposal.observation.place_guess}
          </:item>
          <:item label="By" value={@proposal.observation.observer}>
            {@proposal.observation.observer}
          </:item>
        </.fact_list>

        <.notice
          :for={need <- @proposal.needs}
          :if={need.kind != :gall or @chosen == nil}
          kind={:warn}
        >
          {need.text}
        </.notice>

        <.section title="Gall" level={3}>
          <p :if={@gall} class="text-ui text-ink"><.taxon_name name={@gall.name} /></p>
          <div :if={!@gall} class="flex flex-col gap-2">
            <p :if={@proposal.gall.why} class="text-meta text-ink-2">{@proposal.gall.why}</p>
            <ul :if={@proposal.gall.candidates != []} class="flex flex-col gap-1">
              <li :for={c <- @proposal.gall.candidates}>
                <label class="flex items-center gap-2 text-ui">
                  <input
                    type="radio"
                    name={"#{@id}-gall"}
                    value={c.id}
                    checked={@chosen && @chosen.id == c.id}
                    class="size-4 accent-brand-fill"
                    phx-click="choose_gall"
                    phx-value-id={c.id}
                    phx-target={@myself}
                  />
                  <.taxon_name name={c.name} />
                </label>
              </li>
            </ul>
            <.typeahead
              id="observation-gall"
              label={if @proposal.gall.candidates == [], do: "The Gall", else: "Or another Gall"}
              placeholder="Find a Gall by name"
              search_event="search_gall"
              select_event="select_gall"
              clear_event="clear_gall"
              query={@gall_query}
              results={@gall_results}
              selected={@chosen}
              display_fn={& &1.name}
              target={@myself}
            />
          </div>
        </.section>

        <.section title="Into your tray" count={length(@proposal.items)} level={3}>
          <p :if={@proposal.items == []} class="text-ui text-muted">
            Nothing to propose from this observation.
          </p>
          <ul :if={@proposal.items != []} class="flex flex-col divide-y divide-line">
            <li
              :for={{item, index} <- Enum.with_index(@proposal.items)}
              data-part="item"
              class="py-1.5"
            >
              <label class="flex items-baseline gap-2 text-ui">
                <input
                  type="checkbox"
                  class="gf-checkbox"
                  checked={MapSet.member?(@selected, index)}
                  phx-click="toggle_item"
                  phx-value-index={index}
                  phx-target={@myself}
                />
                <span class="text-ink">{item.text}</span>
                <span :if={item.why} class="text-meta text-muted">{item.why}</span>
              </label>
            </li>
          </ul>
          <div class="mt-block flex flex-wrap items-center gap-3">
            <.button
              id={"#{@id}-add"}
              variant="primary"
              phx-click="add"
              phx-target={@myself}
              disabled={@chosen == nil or MapSet.size(@selected) == 0}
            >
              Add {MapSet.size(@selected)} to your tray
            </.button>
            <span class="text-meta text-muted">
              Each with this observation as its evidence.
            </span>
          </div>
          <.notice :if={@added && @added.count > 0} kind={:ok} class="mt-block">
            {@added.count} {if @added.count == 1, do: "change is", else: "changes are"} in your tray. Review and apply them from the tray at the foot of the screen.
          </.notice>
          <.notice :if={@added && @added.errors != []} kind={:danger} class="mt-block">
            <span :for={e <- @added.errors} class="block">{e}</span>
          </.notice>
        </.section>

        <.live_component
          :if={@chosen}
          module={InatImportComponent}
          id={"#{@id}-photos"}
          owner={{:gall, @chosen.id}}
          uploader={@curator.name}
        />
      </div>
    </div>
    """
  end
end
