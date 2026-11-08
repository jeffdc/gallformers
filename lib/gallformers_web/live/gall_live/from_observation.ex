defmodule GallformersWeb.GallLive.FromObservation do
  @moduledoc """
  Add from observation in the Fact inspector (matter `87a1`, its "Add from
  observation (in the inspector)"; matter `ec2c`): the `fact_inspector`'s
  observation state on a Gall's page in Edit mode, in place of the old
  dialog (`GallformersWeb.ObservationIntake`).

  A link or number reads the observation
  (`Gallformers.Curation.from_observation/3`, this Gall given):

    * its card: the thumbnail, the link, what it is identified as, when and
      where it was seen, by whom, its quality grade as a chip;
    * a warning, never a refusal, when its taxon isn't the Gall's Inducer,
      naming that taxon and linking its Gall; and when it isn't Research
      Grade, saying so;
    * what it shows: each proposal ticked (or not), New or Already held
      (the observation adds evidence), its reason under it; the ticked ones
      are previewed on the page, marked proposed (the page hears
      `{#{inspect(__MODULE__)}, :proposing, keys}`);
    * a missing Host asked for here, through the shared plant search;
    * its photos, each ticked to go in the tray as an editorial change, and
      whether the Gall has photos from this observation already;
    * one "Add N to your tray": each Fact a Gallformers statement with the
      observation as its evidence, each photo a `:photo` item. The page
      hears `{#{inspect(__MODULE__)}, :added}`.
  """
  use GallformersWeb, :live_component

  import GallformersWeb.FactsComponents, only: [fact_inspector: 1, grade_words: 1]

  alias Gallformers.Curation
  alias Gallformers.Images
  alias GallformersWeb.Choices

  @results 8

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       url: "",
       error: nil,
       proposal: nil,
       items: [],
       ticked: MapSet.new(),
       photos: MapSet.new(),
       plant_query: "",
       plant_results: []
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, Map.take(assigns, [:id, :gall, :curator]))

    # An observation given (`?observation=`) is read at once, the first time.
    case assigns[:observation] do
      id when is_binary(id) and id != "" ->
        if socket.assigns.url == "", do: {:ok, read(socket, id)}, else: {:ok, socket}

      _ ->
        {:ok, socket}
    end
  end

  # -- events --------------------------------------------------------------------------

  @impl true
  def handle_event("read", %{"url" => url}, socket), do: {:noreply, read(socket, url)}

  def handle_event("tick", %{"index" => index}, socket) do
    socket = update(socket, :ticked, &toggle(&1, String.to_integer(index)))
    {:noreply, proposing(socket)}
  end

  def handle_event("tick_photo", %{"id" => id}, socket),
    do: {:noreply, update(socket, :photos, &toggle(&1, String.to_integer(id)))}

  def handle_event("search_plant", %{"value" => query}, socket),
    do:
      {:noreply,
       assign(socket, plant_query: query, plant_results: Choices.hosts(query, @results))}

  def handle_event("select_plant", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.plant_results, &(to_string(&1.id) == id)) do
      nil -> {:noreply, socket}
      plant -> {:noreply, give_host(socket, plant)}
    end
  end

  def handle_event("clear_plant", _params, socket),
    do: {:noreply, assign(socket, plant_query: "", plant_results: [])}

  def handle_event("add", _params, socket), do: {:noreply, add(socket)}

  defp read(socket, url) do
    %{curator: curator, gall: gall} = socket.assigns

    case Curation.from_observation(curator, String.trim(url), gall.id) do
      {:ok, proposal} ->
        ticked =
          for {item, i} <- Enum.with_index(proposal.items),
              item.selected,
              into: MapSet.new(),
              do: i

        socket
        |> assign(url: url, error: nil, proposal: proposal, items: proposal.items, ticked: ticked)
        |> assign(photos: MapSet.new())
        |> proposing()

      {:error, reason} ->
        socket
        |> assign(url: url, error: error_text(reason), proposal: nil, items: [])
        |> proposing()
    end
  end

  # A Host the curator gives: one more proposal, ticked.
  defp give_host(socket, plant) do
    item = %{
      role: :host,
      spec: %{kind: :fact, gall_id: socket.assigns.gall.id, action: :add, key: {:host, plant.id}},
      text: "Add host: " <> plant.name,
      why: "The Host you gave.",
      selected: true,
      held: false
    }

    index = length(socket.assigns.items)

    socket
    |> assign(items: socket.assigns.items ++ [item], plant_query: "", plant_results: [])
    |> update(:ticked, &MapSet.put(&1, index))
    |> proposing()
  end

  defp add(socket) do
    %{proposal: proposal, items: items, ticked: ticked, photos: photos} = socket.assigns
    %{curator: curator, gall: gall} = socket.assigns

    facts =
      for {item, i} <- Enum.with_index(items), i in ticked do
        with {:ok, added} <- Curation.add_item(curator, %{item.spec | gall_id: gall.id}),
             {:ok, _} <- Curation.set_item_evidence(curator, added.id, proposal.evidence),
             do: :ok
      end

    pictures =
      for id <- photos do
        spec = %{
          kind: :photo,
          gall_id: gall.id,
          observation_id: proposal.observation.id,
          photo_id: id
        }

        with {:ok, _} <- Curation.add_item(curator, spec), do: :ok
      end

    case Enum.reject(facts ++ pictures, &(&1 == :ok)) do
      [] ->
        send(self(), {__MODULE__, :added})
        socket

      [{:error, reason} | _] ->
        assign(socket, error: "It couldn't all go in your tray (#{reason}).")
    end
  end

  defp toggle(set, x), do: if(x in set, do: MapSet.delete(set, x), else: MapSet.put(set, x))

  # The ticked proposals' keys, for the page to preview.
  defp proposing(socket) do
    %{items: items, ticked: ticked} = socket.assigns
    keys = for {item, i} <- Enum.with_index(items), i in ticked, not item.held, do: item.spec.key
    send(self(), {__MODULE__, :proposing, keys})
    socket
  end

  defp error_text(:invalid_input), do: "That isn't an iNaturalist observation's link or number."
  defp error_text(:not_found), do: "iNaturalist has no such observation."
  defp error_text(:unavailable), do: "iNaturalist couldn't be reached. Try again in a moment."
  defp error_text(:no_such_gall), do: "The Gall is gone."

  # -- the inspector ------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        count: MapSet.size(assigns.ticked) + MapSet.size(assigns.photos),
        has_photos?: assigns.proposal != nil and photos_from?(assigns.gall, assigns.proposal)
      )

    ~H"""
    <div id={@id}>
      <.fact_inspector
        id="fact-inspector"
        state={:observation}
        of={@gall}
        editing
        on_close="close_fact"
      >
        <form
          id="observation-form"
          phx-submit="read"
          phx-target={@myself}
          class="flex items-end gap-2"
        >
          <div class="flex-1">
            <.input
              type="text"
              name="url"
              value={@url}
              label="iNaturalist observation"
              placeholder="A link or its number"
            />
          </div>
          <.button type="submit">Read</.button>
        </form>
        <p :if={@error} data-part="error" class="mt-2 text-meta text-danger">{@error}</p>

        <div :if={@proposal} class="mt-4 flex flex-col gap-4">
          <.card proposal={@proposal} />

          <.notice
            :if={!@proposal.taxon.matches?}
            data-part="taxon-notice"
            kind={:warn}
            title="Not this Gall's Inducer"
          >
            iNaturalist identifies it as
            <.taxon_name name={@proposal.taxon.name} />. Check it's the right observation.
            <span :if={@proposal.taxon.galls != []}>
              Its Gall:
              <.link
                :for={gall <- @proposal.taxon.galls}
                navigate={"/gall/#{gall.id}?edit"}
                class="mr-2"
              >
                <.gall_name name={gall.name} />
              </.link>
            </span>
          </.notice>
          <.notice
            :if={@proposal.inat_observation.quality_grade != "research"}
            data-part="grade-notice"
            kind={:warn}
            title={grade_words(@proposal.inat_observation.quality_grade) || "No quality grade"}
          >
            Not Research Grade: its identification isn't confirmed by the community. It can still be evidence; the statements will say so.
          </.notice>

          <div class="flex flex-col gap-2">
            <h3 class="text-meta font-semibold text-muted">What it shows</h3>
            <label
              :for={{item, i} <- Enum.with_index(@items)}
              data-part="proposal"
              class="flex cursor-pointer items-start gap-2 text-ui"
            >
              <input
                type="checkbox"
                class="gf-checkbox mt-1"
                checked={i in @ticked}
                phx-click="tick"
                phx-value-index={i}
                phx-target={@myself}
              />
              <span class="flex flex-col">
                <span>
                  {item.text}
                  <.chip size="sm" variant={if item.held, do: :info, else: :ok}>
                    {if item.held, do: "Already held", else: "New"}
                  </.chip>
                </span>
                <span class="text-meta text-muted">{item.why}</span>
              </span>
            </label>
            <p :for={need <- @proposal.needs} class="text-meta text-ink-2">{need.text}</p>
            <div :if={host_needed?(@proposal)} data-part="need-host">
              <.typeahead
                id="observation-host"
                label="Add a host"
                placeholder="A plant's name: species, genus or section"
                query={@plant_query}
                results={@plant_results}
                search_event="search_plant"
                select_event="select_plant"
                clear_event="clear_plant"
                display_fn={& &1.name}
                group_key={:group}
                target={@myself}
              >
                <:result :let={plant}>
                  <.taxon_name name={plant.name} />
                  <span class="text-caption text-muted">{plant.meta}</span>
                </:result>
              </.typeahead>
            </div>
          </div>

          <div :if={@proposal.photos != []} class="flex flex-col gap-2">
            <h3 class="text-meta font-semibold text-muted">Its photos, for this Gall</h3>
            <p :if={@has_photos?} class="text-meta text-ink-2">
              This Gall already has photos from this observation.
            </p>
            <div class="flex flex-wrap gap-2">
              <label
                :for={photo <- @proposal.photos}
                data-part="photo"
                class="flex cursor-pointer flex-col gap-1"
              >
                <img src={photo.thumbnail_url} alt="" class="size-24 rounded-ctl object-cover" />
                <span class="flex items-center gap-1 text-caption text-muted">
                  <input
                    type="checkbox"
                    class="gf-checkbox"
                    checked={photo.id in @photos}
                    phx-click="tick_photo"
                    phx-value-id={photo.id}
                    phx-target={@myself}
                  />
                  {photo.mapped_license}
                </span>
              </label>
            </div>
          </div>

          <div class="flex flex-col gap-1 border-t border-line pt-3">
            <.button variant="primary" phx-click="add" phx-target={@myself} disabled={@count == 0}>
              Add {@count} to your tray
            </.button>
            <p class="text-meta text-muted">
              Each a Gallformers statement based on this observation; photos as editorial changes.
            </p>
          </div>
        </div>
      </.fact_inspector>
    </div>
    """
  end

  attr :proposal, :map, required: true

  # The observation's card.
  defp card(assigns) do
    assigns =
      assign(assigns, o: assigns.proposal.observation, obs: assigns.proposal.inat_observation)

    ~H"""
    <div data-part="card" class="flex gap-3">
      <img
        :if={@proposal.photos != []}
        src={hd(@proposal.photos).thumbnail_url}
        alt=""
        class="size-20 shrink-0 rounded-ctl object-cover"
      />
      <div class="flex min-w-0 flex-col gap-0.5 text-meta text-ink-2">
        <p class="text-ui text-ink">
          <.link href={@o.url} target="_blank" rel="noreferrer">Observation {@o.id} ↗</.link>
        </p>
        <p>Identified as <.taxon_name name={@o.taxon_name || "nothing"} /></p>
        <p>Seen {@o.observed_on || "on no date given"} · {@o.place_guess}</p>
        <p>By {@o.observer}</p>
        <p>
          <.chip variant={if @obs.quality_grade == "research", do: :ok, else: :warn}>
            {grade_words(@obs.quality_grade) || "No quality grade"}
          </.chip>
        </p>
      </div>
    </div>
    """
  end

  defp host_needed?(proposal), do: Enum.any?(proposal.needs, &(&1.kind == :host))

  # The Gall has photos imported from this observation already.
  defp photos_from?(gall, proposal) do
    suffix = "/#{proposal.observation.id}"

    gall.id
    |> Images.list_images_for_gall()
    |> Enum.any?(&(is_binary(&1.sourcelink) and String.ends_with?(&1.sourcelink, suffix)))
  end
end
