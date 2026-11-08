defmodule GallformersWeb.Dev.Mockups.FactInspectorLive do
  @moduledoc """
  Mockup (matter `d3b0`, "The Fact inspector"): the Gall page where the
  Fact viewer and the Fact editor are one thing.
  `/dev/mockups/fact-inspector/:id` (reading), `?edit` (editing).

  The page reads as the Gall page does; every Fact-backed value (Inducer,
  Hosts, Trait values, range places, common names) is a `fact_ref`.
  Selecting one opens the `fact_inspector` beside the page (in the rail's
  place on wide screens, a bottom sheet on phones): the Fact in words, its
  standing and every Source's statement of it, newest first. In Edit mode
  the same inspector adds the actions, by authority: "Gallformers says"
  (withdraw, change, note) first, and a level deeper the rarer correction
  of how a Source was read. Each group has one Add, which opens the
  inspector on a new Fact.

  Real: the Gall, its Facts and every statement (`FactEditMock.gall_panel/1`),
  the tray and Review and apply (`FactEditMock`, nothing is written).
  PROPOSED: `fact_ref`, `fact_inspector` and its actions.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Catalog
  alias Gallformers.Catalog.ReadModels.GallPage
  alias Gallformers.Images.Image
  alias GallformersWeb.Dev.Mockups.FactEditMock, as: Mock

  import GallformersWeb.Dev.Mockups.FactEditMock, only: [authority_tray: 1, review_dialog: 1]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    gall_id = String.to_integer(id)

    case Catalog.gall_page(gall_id) do
      {:ok, %GallPage{} = gall} ->
        panel = Mock.gall_panel(gall_id)

        {:ok,
         socket
         |> assign(
           page_title: "Mockup: " <> gall.name,
           page_noindex: true,
           gall: gall,
           photo: photo(gall.images),
           panel: panel,
           cats: Map.new(panel, &{&1.id, &1}),
           selected: nil,
           action: nil,
           corrections?: false,
           hint_dismissed?: false,
           obs: empty_obs(),
           curator: GallformersWeb.Live.UserAuth.curator(socket.assigns.current_user),
           editing: false
         )
         |> Mock.init([])}

      :not_found ->
        raise GallformersWeb.NotFoundError, "No gall #{id}"
    end
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, assign(socket, editing: Map.has_key?(params, "edit"), action: nil)}

  defp empty_obs,
    do: %{url: "", proposal: nil, error: nil, items: MapSet.new(), photos: MapSet.new()}

  defp photo([]), do: nil

  defp photo([img | _]),
    do: %{url: "#{Image.base_url()}/#{img.path}", creator: img.creator, license: img.license}

  # -- events ---------------------------------------------------------------------

  @impl true
  def handle_event("select", %{"key" => key}, socket),
    do: {:noreply, assign(socket, selected: key, action: nil, corrections?: false)}

  def handle_event("close", _params, socket),
    do: {:noreply, assign(socket, selected: nil, action: nil, corrections?: false)}

  def handle_event("add", %{"category" => category}, socket),
    do: {:noreply, assign(socket, selected: {:new, category}, action: "add", corrections?: false)}

  def handle_event("act", %{"action" => action}, socket),
    do: {:noreply, assign(socket, action: action)}

  def handle_event("correct", %{"source" => source_id}, socket),
    do: {:noreply, assign(socket, action: {:correct, String.to_integer(source_id)})}

  def handle_event("show_corrections", _params, socket),
    do: {:noreply, assign(socket, corrections?: !socket.assigns.corrections?, action: nil)}

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, action: nil)}

  def handle_event("observe", _params, socket),
    do: {:noreply, assign(socket, selected: :observation, action: nil, obs: empty_obs())}

  def handle_event("read_obs", %{"url" => url}, socket) do
    case Gallformers.Curation.from_observation(socket.assigns.curator, String.trim(url), nil) do
      {:ok, proposal} ->
        picked =
          for {i, idx} <- Enum.with_index(proposal.items), i.selected, into: MapSet.new(), do: idx

        {:noreply,
         assign(socket, obs: %{empty_obs() | url: url, proposal: proposal, items: picked})}

      {:error, reason} ->
        {:noreply, assign(socket, obs: %{empty_obs() | url: url, error: obs_error(reason)})}
    end
  end

  def handle_event("toggle_obs_item", %{"index" => i}, socket),
    do: {:noreply, update(socket, :obs, &%{&1 | items: toggle(&1.items, String.to_integer(i))})}

  def handle_event("toggle_obs_photo", %{"id" => id}, socket),
    do:
      {:noreply, update(socket, :obs, &%{&1 | photos: toggle(&1.photos, String.to_integer(id))})}

  def handle_event("add_obs", _params, socket) do
    %{proposal: proposal, items: picked, photos: photos} = socket.assigns.obs
    o = proposal.observation

    based_on =
      "iNaturalist observation #{o.id} (#{grade_words(proposal.inat_observation.quality_grade)})"

    facts =
      for {item, idx} <- Enum.with_index(proposal.items), idx in picked do
        %{
          key: nil,
          group: :gallformers,
          kind: :fact,
          text: "#{item.text}, based on #{based_on}",
          flags: [%{kind: :adds_statement, text: "Gallformers' statement, dated when applied"}],
          evidence: nil
        }
      end

    pics =
      for p <- proposal.photos, p.id in photos do
        %{
          field: :photo,
          group: :editorial,
          kind: :editorial,
          text:
            "Add photo #{p.id} by #{o.observer} (#{p.mapped_license}) from observation #{o.id}",
          flags: [%{kind: :editorial, text: "editorial"}]
        }
      end

    socket =
      Enum.reduce(facts ++ pics, socket, fn item, socket ->
        id = socket.assigns.mock_next

        assign(socket,
          mock_items: socket.assigns.mock_items ++ [Map.put(item, :id, id)],
          mock_next: id + 1
        )
      end)

    {:noreply,
     socket
     |> assign(selected: nil, obs: empty_obs(), mock_tray_open: true)
     |> put_flash(:info, "Added #{length(facts ++ pics)} to your tray")}
  end

  def handle_event("dismiss_hint", _params, socket),
    do: {:noreply, assign(socket, hint_dismissed?: true)}

  def handle_event("submit", params, socket) do
    item = tray_item(socket.assigns, params)
    id = socket.assigns.mock_next

    {:noreply,
     socket
     |> assign(
       mock_items: socket.assigns.mock_items ++ [Map.put(item, :id, id)],
       mock_next: id + 1,
       action: nil,
       mock_tray_open: true
     )
     |> put_flash(:info, "Added to your tray")}
  end

  def handle_event(event, params, socket) do
    if event in Mock.events(),
      do: {:noreply, Mock.handle(event, params, socket)},
      else: {:noreply, socket}
  end

  defp toggle(set, x), do: if(x in set, do: MapSet.delete(set, x), else: MapSet.put(set, x))

  defp obs_error(:invalid_input), do: "That isn't an iNaturalist observation's link or number."
  defp obs_error(:not_found), do: "iNaturalist has no such observation."
  defp obs_error(:unavailable), do: "iNaturalist couldn't be reached. Try again in a moment."
  defp obs_error(reason), do: to_string(reason)

  defp grade_words("research"), do: "Research Grade"
  defp grade_words("needs_id"), do: "Needs ID"
  defp grade_words("casual"), do: "Casual"
  defp grade_words(_), do: "grade unknown"

  # The Gall has photos imported from observation `id` already.
  defp photos_from?(gall, id),
    do:
      Enum.any?(
        gall.images,
        &(is_binary(&1.sourcelink) and String.ends_with?(&1.sourcelink, "/#{id}"))
      )

  # The observation's taxon is this Gall's Inducer (or one of them).
  defp same_taxon?(%{taxon_name: nil}, _gall), do: true
  defp same_taxon?(%{taxon_name: name}, gall), do: Enum.any?(gall.inducers, &(&1.name == name))

  # What the observation's proposals add to a page group, while picked.
  defp proposed(%{proposal: nil}, _role), do: []

  defp proposed(%{proposal: p, items: picked}, role) do
    for {item, idx} <- Enum.with_index(p.items),
        idx in picked,
        item.role == role,
        do: String.replace_prefix(item.text, "Add ", "")
  end

  # New, or a Fact this Gall already holds (the observation adds evidence).
  defp held?(%{spec: %{key: {:host, id}}}, cats),
    do: Enum.any?(cats["hosts"].facts, &(&1.ref == {:host, id}))

  defp held?(%{text: text}, cats) do
    Enum.any?(cats["range"].facts, fn f ->
      match?({:prefixed, "recorded in", _}, f.label) and
        String.contains?(text, "recorded in #{elem(f.label, 2)}")
    end)
  end

  defp tray_item(assigns, params) do
    why = String.trim(params["why"] || "")
    value = String.trim(params["value"] || "")
    fact = current_fact(assigns)

    {group, flag, text} =
      case {assigns.action, fact} do
        {"add", _} ->
          {:gallformers, gallformers_flag(),
           "Add #{add_what(assigns.selected)} #{value}#{because(why)}"}

        {"confirm", fact} ->
          {:gallformers, gallformers_flag(), "Confirm #{fact.text}#{because(why)}"}

        {"withdraw", fact} ->
          {:gallformers, gallformers_flag(), "Deny #{fact.text}#{because(why)}"}

        {"change", fact} ->
          {:gallformers, gallformers_flag(), "Change #{fact.text} to #{value}#{because(why)}"}

        {"note", fact} ->
          {:gallformers, gallformers_flag(), "Note on #{fact.text}: #{why}"}

        {{:correct, source_id}, fact} ->
          line = Enum.find(fact.lines, &(&1.source_id == source_id))

          {{:source, source_id, line.name},
           %{kind: :adds_statement, text: "#{line.name}'s statement, at its date (#{line.date})"},
           "Fix our reading of #{line.name}: #{fact.text} → #{value}#{because(why)}"}
      end

    %{
      key: fact && fact.key,
      group: group,
      kind: :fact,
      text: text,
      flags: [flag],
      evidence: nil
    }
  end

  defp gallformers_flag,
    do: %{kind: :adds_statement, text: "Gallformers' statement, dated when applied"}

  defp because(""), do: ""
  defp because(why), do: " (#{why})"

  defp add_what({:new, "hosts"}), do: "the Host"
  defp add_what({:new, "aliases"}), do: "the common name"
  defp add_what({:new, "range"}), do: "the place"
  defp add_what({:new, "traits-" <> trait}), do: "the #{Mock.trait_label(trait)} value"
  defp add_what(_), do: "the Fact"

  defp current_fact(%{selected: key, panel: panel}) when is_binary(key),
    do: Mock.find_fact(panel, key)

  defp current_fact(_assigns), do: nil

  # -- the page ---------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns = assign(assigns, fact: current_fact(assigns))

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section pb-section">
        <.notice kind={:warn} title="Mockup: the Fact inspector">
          Matter d3b0. Select any underlined value: the inspector shows who says so. {if @editing,
            do: "In Edit mode it also holds the actions; each one goes into your tray.",
            else: "Edit adds the actions to the same inspector."} Real: the Gall, its Facts and every Source's statement. Not real: actions and tray write nothing.
          PROPOSED: fact_ref (the underlined value), fact_inspector.
        </.notice>

        <.page_header>
          <:title><.gall_name name={@gall.name} undescribed={@gall.undescribed?} /></:title>
          <:chip :if={!@gall.datacomplete} variant={:warn}>In progress</:chip>
          <:action>
            <.button
              :if={!@editing}
              icon="ph-pencil-simple"
              patch={~p"/dev/mockups/fact-inspector/#{@gall.id}?edit"}
            >
              Edit
            </.button>
            <.button :if={@editing} icon="ph-eye" phx-click="observe">
              Add from observation…
            </.button>
            <.button
              :if={@editing}
              variant="primary"
              icon="ph-pencil-simple"
              patch={~p"/dev/mockups/fact-inspector/#{@gall.id}"}
            >
              Editing · Done
            </.button>
          </:action>
        </.page_header>

        <div class="grid items-start gap-section lg:grid-cols-12">
          <div class="flex min-w-0 flex-col gap-section lg:col-span-8">
            <%!-- PROPOSED: the hint that teaches the underline; a reader can dismiss it (kept per browser) --%>
            <p
              :if={!@editing and !@hint_dismissed?}
              id="fact-hint"
              class="flex items-start gap-2 text-ui text-ink-2"
            >
              <.icon name="ph-info" class="mt-0.5 size-4 shrink-0 text-muted" />
              <span class="flex-1">
                Underlined values show the Sources that state them. Select one to see who says so.
              </span>
              <.button
                size="sm"
                variant="ghost"
                icon="ph-x"
                icon_only
                label="Dismiss"
                phx-click="dismiss_hint"
              />
            </p>
            <.notice :if={@editing} title="Editing">
              Select a value to change it, or Add to a group. The page stays as readers see it; every change waits in your tray until you apply it.
            </.notice>

            <.section title="Inducer">
              <.fact_group cat={@cats["inducer"]} selected={@selected} editing={false} />
            </.section>

            <.section title="Hosts" count={length(@cats["hosts"].facts)}>
              <:aside :if={@editing}>
                <.add_link category="hosts">Add a host</.add_link>
              </:aside>
              <.fact_group
                cat={@cats["hosts"]}
                selected={@selected}
                editing={@editing}
                class="grid gap-x-6 gap-y-1 sm:grid-cols-2 xl:grid-cols-3"
              />
              <.proposed_values :if={@selected == :observation} values={proposed(@obs, :host)} />
            </.section>

            <.section title="Traits">
              <.fact_list columns={2} missing_label={nil}>
                <:item :for={sub <- @cats["traits"].subs} label={sub.label}>
                  <span class="flex flex-wrap items-baseline gap-x-2 gap-y-1">
                    <.fact_ref :for={f <- sub.facts} fact={f} selected={@selected} />
                    <.add_link :if={@editing} category={sub.id} small>Add</.add_link>
                  </span>
                </:item>
              </.fact_list>
              <p
                :if={@cats["traits"].missing != [] and !@editing}
                class="mt-2 text-meta text-muted"
              >
                Not recorded: {@cats["traits"].missing
                |> Enum.map(&String.downcase(Mock.trait_label(&1)))
                |> Enum.join(", ")}
              </p>
              <p
                :if={@cats["traits"].missing != [] and @editing}
                class="mt-2 flex flex-wrap items-baseline gap-x-3 gap-y-1 text-meta text-muted"
              >
                Not recorded:
                <.add_link :for={t <- @cats["traits"].missing} category={"traits-#{t}"} small>
                  {String.downcase(Mock.trait_label(t))}
                </.add_link>
              </p>
            </.section>

            <.section title="Range">
              <:aside :if={@editing}><.add_link category="range">Add a place</.add_link></:aside>
              <p class="mb-2 text-meta text-muted">
                Where the Hosts grow, adjusted by these places; the map is left out of this mockup.
              </p>
              <.fact_group
                cat={@cats["range"]}
                selected={@selected}
                editing={@editing}
                class="flex flex-wrap gap-x-4 gap-y-1"
              />
              <.proposed_values :if={@selected == :observation} values={proposed(@obs, :occurrence)} />
            </.section>

            <.section title="Common names">
              <:aside :if={@editing}>
                <.add_link category="aliases">Add a common name</.add_link>
              </:aside>
              <.fact_group
                cat={@cats["aliases"]}
                selected={@selected}
                editing={@editing}
                class="flex flex-wrap gap-x-4 gap-y-1"
              />
            </.section>

            <.section title="Sources" count={length(@gall.sources)}>
              <ul class="flex flex-col gap-1 text-ui">
                <li :for={s <- Enum.reject(@gall.sources, & &1.note?)} class="flex gap-3">
                  <span class="w-12 shrink-0 tabular-nums text-muted">{s.pubyear}</span>
                  <.link navigate={"/source/#{s.id}"}>{s.title}</.link>
                </li>
              </ul>
            </.section>
          </div>

          <aside class="flex flex-col gap-block lg:sticky lg:top-20 lg:col-span-4">
            <div :if={@photo} class={[@selected && "hidden lg:hidden"]}>
              <img src={@photo.url} alt="" class="aspect-4/3 w-full rounded-panel object-cover" />
              <p class="mt-1 text-caption text-muted">
                Photo: {@photo.creator}{if @photo.license, do: " · #{@photo.license}"}
              </p>
            </div>
            <p :if={!@selected} class="hidden text-meta text-muted lg:block">
              Select an underlined value to see who says so.
            </p>

            <%!-- PROPOSED: fact_inspector. In the rail's place on wide screens, a bottom sheet on phones. --%>
            <section
              :if={@selected}
              id="fact-inspector"
              aria-label="Fact"
              class="fixed inset-x-0 bottom-0 z-40 flex max-h-[70vh] flex-col overflow-y-auto rounded-t-panel border-t border-line bg-surface p-panel shadow-float lg:static lg:z-auto lg:max-h-[calc(100vh-7rem)] lg:rounded-panel lg:border lg:shadow-none"
            >
              <.inspector
                fact={@fact}
                selected={@selected}
                gall={@gall}
                editing={@editing}
                action={@action}
                corrections?={@corrections?}
                obs={@obs}
                cats={@cats}
              />
            </section>
          </aside>
        </div>
      </div>

      <.authority_tray :if={@editing} items={@mock_items} open={@mock_tray_open} />
      <.review_dialog
        show={@editing and @mock_review}
        items={@mock_items}
        evidence={@mock_evidence}
        confirmed={@mock_confirmed}
        source={@mock_evidence_source}
        source_query={@mock_source_query}
        source_results={@mock_source_results}
      />
    </Layouts.app>
    """
  end

  # -- PROPOSED: fact_ref, a Fact-backed value -----------------------------------

  attr :cat, :map, required: true
  attr :selected, :any, required: true
  attr :editing, :boolean, required: true
  attr :class, :any, default: "flex flex-col gap-1"

  defp fact_group(assigns) do
    ~H"""
    <div class={@class}>
      <.fact_ref :for={f <- @cat.facts} fact={f} selected={@selected} />
      <p :if={@cat.facts == []} class="text-ui text-muted">{@cat.empty}</p>
    </div>
    """
  end

  attr :fact, :map, required: true
  attr :selected, :any, required: true

  defp fact_ref(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="select"
      phx-value-key={@fact.key}
      aria-pressed={to_string(@selected == @fact.key)}
      aria-controls="fact-inspector"
      title="Who says so?"
      class={[
        "w-fit rounded-ctl px-0.5 text-left text-ui text-ink underline decoration-line-strong decoration-dotted underline-offset-4 hover:decoration-ink",
        @selected == @fact.key && "bg-sky-soft decoration-ink"
      ]}
    >
      <.label_text label={@fact.label} />
    </button>
    """
  end

  attr :label, :any, required: true

  defp label_text(%{label: {:taxon, _name, _rank}} = assigns),
    do: ~H|<.taxon_name name={elem(@label, 1)} />|

  defp label_text(%{label: {:prefixed, _prefix, _text}} = assigns),
    do: ~H|<span class="text-muted">{elem(@label, 1)}</span> {elem(@label, 2)}|

  defp label_text(%{label: {_kind, text}} = assigns) when is_binary(text),
    do: ~H|{elem(@label, 1)}|

  defp label_text(assigns), do: ~H|not settled|

  attr :values, :list, required: true

  # PROPOSED: a proposal shown where it would land on the page.
  defp proposed_values(assigns) do
    ~H"""
    <div :if={@values != []} class="mt-2 flex flex-wrap gap-2">
      <span
        :for={v <- @values}
        class="inline-flex items-center gap-2 rounded-ctl bg-sky-soft px-2 py-0.5 text-ui text-ink"
      >
        {v}
        <.chip size="sm" variant={:info}>proposed</.chip>
      </span>
    </div>
    """
  end

  attr :category, :string, required: true
  attr :small, :boolean, default: false
  slot :inner_block, required: true

  defp add_link(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="add"
      phx-value-category={@category}
      class={[
        "inline-flex items-center gap-1 text-link hover:underline",
        if(@small, do: "text-meta", else: "text-ui")
      ]}
    >
      <.icon name="ph-plus" class="size-3.5" />{render_slot(@inner_block)}
    </button>
    """
  end

  # -- PROPOSED: fact_inspector ------------------------------------------------------

  attr :fact, :map, default: nil
  attr :selected, :any, required: true
  attr :gall, :map, required: true
  attr :editing, :boolean, required: true
  attr :action, :any, required: true
  attr :corrections?, :boolean, required: true
  attr :obs, :map, default: nil
  attr :cats, :map, default: %{}

  # PROPOSED: Add from observation, the inspector's observation state.
  defp inspector(%{selected: :observation} = assigns) do
    assigns =
      assign(assigns,
        p: assigns.obs.proposal,
        o: assigns.obs.proposal && assigns.obs.proposal.inat_observation,
        count: MapSet.size(assigns.obs.items) + MapSet.size(assigns.obs.photos)
      )

    ~H"""
    <.inspector_head kind="Add from observation" />
    <form phx-submit="read_obs" class="flex items-end gap-2">
      <div class="flex-1">
        <.input
          type="text"
          name="url"
          value={@obs.url}
          label="iNaturalist observation"
          placeholder="A link or its number"
        />
      </div>
      <.button type="submit">Read</.button>
    </form>
    <p :if={@obs.error} class="mt-2 text-meta text-danger">{@obs.error}</p>

    <div :if={@p} class="mt-4 flex flex-col gap-4">
      <div class="flex gap-3">
        <img
          :if={@p.photos != []}
          src={hd(@p.photos).thumbnail_url}
          alt=""
          class="size-20 shrink-0 rounded-ctl object-cover"
        />
        <div class="flex min-w-0 flex-col gap-0.5 text-meta text-ink-2">
          <p class="text-ui text-ink">
            <.link href={@p.observation.url} target="_blank" rel="noreferrer">
              Observation {@p.observation.id} ↗
            </.link>
          </p>
          <p>Identified as <.taxon_name name={@p.observation.taxon_name || "nothing"} /></p>
          <p>Seen {@p.observation.observed_on} · {@p.observation.place_guess}</p>
          <p>By {@p.observation.observer}</p>
          <p>
            <.chip variant={if @o.quality_grade == "research", do: :ok, else: :warn}>
              {grade_words(@o.quality_grade)}
            </.chip>
          </p>
        </div>
      </div>

      <.notice :if={!same_taxon?(@p.observation, @gall)} kind={:warn} title="Not this Gall's Inducer">
        iNaturalist identifies it as <.taxon_name name={@p.observation.taxon_name} />, not
        <.taxon_name name={Enum.map_join(@gall.inducers, ", ", & &1.name)} />. Check it's the right observation.
        <span :if={@p.gall.candidates != []}>
          Its Gall:
          <.link :for={c <- @p.gall.candidates} navigate={"/dev/mockups/fact-inspector/#{c.id}?edit"}>
            <.gall_name name={c.name} />
          </.link>
        </span>
      </.notice>
      <.notice :if={@o.quality_grade != "research"} kind={:warn} title={grade_words(@o.quality_grade)}>
        Not Research Grade: its identification isn't confirmed by the community. It can still be evidence; the statements will say so.
      </.notice>

      <div class="flex flex-col gap-2">
        <h3 class="text-meta font-semibold text-muted">What it shows</h3>
        <label
          :for={{item, idx} <- Enum.with_index(@p.items)}
          class="flex cursor-pointer items-start gap-2 text-ui"
        >
          <input
            type="checkbox"
            class="gf-checkbox mt-1"
            checked={idx in @obs.items}
            phx-click="toggle_obs_item"
            phx-value-index={idx}
          />
          <span class="flex flex-col">
            <span>
              {item.text}
              <.chip size="sm" variant={if held?(item, @cats), do: :info, else: :ok}>
                {if held?(item, @cats), do: "Already held", else: "New"}
              </.chip>
            </span>
            <span class="text-meta text-muted">{item.why}</span>
          </span>
        </label>
        <div :for={need <- @p.needs} class="flex flex-col gap-1">
          <p class="text-meta text-ink-2">{need.text}</p>
          <.input
            :if={need.kind == :host}
            type="text"
            name="host"
            value=""
            label="Add a host"
            placeholder="A plant's name (the shared plant search)"
          />
        </div>
      </div>

      <div :if={@p.photos != []} class="flex flex-col gap-2">
        <h3 class="text-meta font-semibold text-muted">Its photos, for this Gall</h3>
        <p :if={photos_from?(@gall, @p.observation.id)} class="text-meta text-ink-2">
          This Gall already has photos from this observation.
        </p>
        <div class="flex flex-wrap gap-2">
          <label :for={ph <- @p.photos} class="flex cursor-pointer flex-col gap-1">
            <img
              src={ph.thumbnail_url}
              alt=""
              class={["size-24 rounded-ctl object-cover", ph.id in @obs.photos && "ring-2 ring-brand"]}
            />
            <span class="flex items-center gap-1 text-caption text-muted">
              <input
                type="checkbox"
                class="gf-checkbox"
                checked={ph.id in @obs.photos}
                phx-click="toggle_obs_photo"
                phx-value-id={ph.id}
              />
              {ph.mapped_license}
            </span>
          </label>
        </div>
      </div>

      <div class="flex flex-col gap-1 border-t border-line pt-3">
        <.button variant="primary" phx-click="add_obs" disabled={@count == 0}>
          Add {@count} to your tray
        </.button>
        <p class="text-meta text-muted">
          Each a Gallformers statement based on this observation; photos as editorial changes.
        </p>
      </div>
    </div>
    """
  end

  defp inspector(%{selected: {:new, category}} = assigns) do
    assigns = assign(assigns, category: category, what: add_what({:new, category}))

    ~H"""
    <.inspector_head kind={"New #{String.replace_prefix(@what, "the ", "")}"} />
    <p class="text-meta text-muted">
      For <.gall_name name={@gall.name} undescribed={@gall.undescribed?} />
    </p>
    <.fact_form action="add" value_label={String.capitalize(String.replace_prefix(@what, "the ", ""))}>
      Your statement is Gallformers', dated when you apply it. Say what it rests on: an observation's link, or why.
    </.fact_form>
    """
  end

  defp inspector(assigns) do
    lines = Enum.reverse(assigns.fact.lines)
    {own, others} = Enum.split_with(lines, & &1.own?)

    assigns =
      assign(assigns,
        # Gallformers pinned first in both modes (in Edit mode even when it
        # has said nothing yet), then the other Sources newest first.
        blocks:
          if(own != [] or assigns.editing, do: [{:gallformers, List.first(own)}], else: []) ++
            Enum.map(others, &{:source, &1}),
        counting: Enum.count(lines, &(&1.state == :counts)),
        unconfirmed?: lines != [] and Enum.all?(lines, &(&1.own? and &1.date == "undated")),
        any_other?: others != []
      )

    ~H"""
    <.inspector_head kind={kind_label(@fact)} />

    <div class="flex flex-col gap-1">
      <p class="font-brand text-section text-ink"><.label_text label={@fact.label} /></p>
      <p class="text-meta text-muted">
        {context_words(@fact)} <.gall_name name={@gall.name} undescribed={@gall.undescribed?} />
      </p>
    </div>

    <p class="mt-3 flex flex-wrap items-center gap-2 text-ui text-ink-2">
      <.chip :if={@unconfirmed?} variant={:warn}>Unconfirmed</.chip>
      <.chip :if={!@unconfirmed?} variant={:ok}>Holds</.chip>
      <span :if={@unconfirmed?}>Only in Gallformers' original data; no other Source states it.</span>
      <span :if={!@unconfirmed?}>
        Stated by {@counting} {if @counting == 1, do: "Source", else: "Sources"}.
      </span>
    </p>

    <div class="mt-4 flex flex-col border-t border-line">
      <div class="flex items-baseline justify-between gap-2 pt-3">
        <h3 class="text-meta font-semibold text-muted">Who says so</h3>
        <span class="text-caption text-muted">Gallformers, then newest first</span>
      </div>

      <%!-- PROPOSED: one block per Source, the same template for each: {Source} says, then its words, its quotes, and the actions that belong to that Source --%>
      <article
        :for={{who, line} <- @blocks}
        class="flex flex-col gap-1 border-b border-line py-3 last:border-b-0"
      >
        <p class="text-ui">
          <span :if={who == :gallformers} class="font-semibold text-ink">Gallformers</span>
          <.link :if={who == :source} navigate={"/source/#{line.source_id}"} class="font-semibold">
            {line.name}
          </.link>
          <span :if={line} class="text-ink">{says(line)}</span>
          <span :if={!line} class="text-ink-2">hasn't stated this</span>
          <span :if={line} class="text-meta text-muted">
            · {when_words(who, line)}{state_words(line.state)}
          </span>
        </p>
        <p :if={line && line.words != []} class="text-meta text-ink-2">
          Written as {Enum.map_join(line.words, ", ", &"“#{&1}”")}
        </p>
        <blockquote
          :for={q <- if(line, do: Enum.take(line.quotes, 2), else: [])}
          class="border-l-2 border-line-strong pl-3 font-serif text-meta text-ink-2"
        >
          <span class="line-clamp-4">{q.quote}</span>
          <span :if={q.page} class="ml-1 font-sans text-caption text-muted">{"p. #{q.page}"}</span>
        </blockquote>
        <p :if={line && length(line.quotes) > 2} class="text-caption text-muted">
          {length(line.quotes) - 2} more quotes
        </p>

        <%!-- Gallformers' own actions: a Gallformers change --%>
        <div :if={@editing and who == :gallformers} class="flex flex-col gap-2 pt-1">
          <div :if={@action == nil} class="flex flex-wrap gap-2">
            <.button :if={!line} size="sm" phx-click="act" phx-value-action="confirm">
              Confirm…
            </.button>
            <.button size="sm" phx-click="act" phx-value-action="change">Change…</.button>
            <.button size="sm" phx-click="act" phx-value-action="withdraw">Deny…</.button>
            <.button size="sm" variant="ghost" phx-click="act" phx-value-action="note">
              Add a note…
            </.button>
          </div>
          <.fact_form :if={@action == "confirm"} action="confirm">
            Gallformers states it too, dated when you apply it: say what it rests on.
          </.fact_form>
          <.fact_form :if={@action == "change"} action="change" value_label="Change it to">
            Gallformers states another value, dated when you apply it.
          </.fact_form>
          <.fact_form :if={@action == "withdraw"} action="withdraw">
            Gallformers says it isn't so, dated when you apply it. The other Sources' statements stay.
          </.fact_form>
          <.fact_form :if={@action == "note"} action="note">
            A note on this Fact, from Gallformers. It changes nothing.
          </.fact_form>
        </div>

        <%!-- Another Source: fixing how it was read, under its authority (a level deeper) --%>
        <div :if={@editing and @corrections? and who == :source} class="pt-1">
          <.button
            :if={@action != {:correct, line.source_id}}
            size="sm"
            variant="ghost"
            phx-click="correct"
            phx-value-source={line.source_id}
          >
            Fix our reading…
          </.button>
          <.fact_form
            :if={@action == {:correct, line.source_id}}
            action="correct"
            value_label={"What #{line.name} actually says"}
          >
            Under {line.name}'s authority, at its date ({line.date}). This doesn't take a position;
            it fixes how the Source was read.
          </.fact_form>
        </div>
      </article>

      <button
        :if={@editing and @any_other?}
        type="button"
        phx-click="show_corrections"
        class="w-fit pt-1 text-meta text-link hover:underline"
      >
        {if @corrections?, do: "Done fixing readings", else: "Found an error in a Source reading?"}
      </button>
    </div>
    """
  end

  # "says so", "says it isn't so"
  defp says(%{stance: :denies}), do: "says it isn't so"
  defp says(_line), do: "says so"

  defp when_words(:gallformers, %{date: "undated"}), do: "original data, undated"
  defp when_words(_who, line), do: line.date

  attr :kind, :string, required: true

  defp inspector_head(assigns) do
    ~H"""
    <div class="mb-2 flex items-center justify-between gap-2">
      <span class="text-meta font-semibold text-muted">{@kind}</span>
      <.button size="sm" variant="ghost" icon="ph-x" icon_only label="Close" phx-click="close" />
    </div>
    """
  end

  attr :action, :string, required: true
  attr :value_label, :string, default: nil
  slot :inner_block, required: true

  defp fact_form(assigns) do
    ~H"""
    <form phx-submit="submit" class="flex flex-col gap-2 rounded-panel bg-surface-2 p-panel">
      <p class="text-meta text-ink-2">{render_slot(@inner_block)}</p>
      <.input :if={@value_label} type="text" name="value" value="" label={@value_label} />
      <.input
        type="textarea"
        name="why"
        value=""
        label={
          if @action == "note", do: "Note", else: "Why (an observation's link, a paper, a reason)"
        }
      />
      <div class="flex gap-2">
        <.button type="submit" variant="primary" size="sm">Add to tray</.button>
        <.button type="button" size="sm" variant="ghost" phx-click="cancel">Cancel</.button>
      </div>
    </form>
    """
  end

  defp kind_label(%{kind: :host}), do: "Host"
  defp kind_label(%{kind: :inducer}), do: "Inducer"
  defp kind_label(%{kind: :trait, trait: trait}), do: Mock.trait_label(trait)
  defp kind_label(%{kind: :range}), do: "Range"
  defp kind_label(%{kind: :alias}), do: "Common name"
  defp kind_label(%{kind: :description}), do: "Description"
  defp kind_label(_fact), do: "Fact"

  defp context_words(%{kind: :host}), do: "A Host of"
  defp context_words(%{kind: :inducer}), do: "The Inducer of"
  defp context_words(%{kind: :trait, trait: trait}), do: "#{Mock.trait_label(trait)} of"
  defp context_words(%{kind: :range}), do: "Where it occurs:"
  defp context_words(%{kind: :alias}), do: "A common name of"
  defp context_words(_fact), do: "About"

  defp state_words(:counts), do: ""
  defp state_words(:awaiting), do: " · awaiting a curator"
  defp state_words(:declined), do: " · declined"
  defp state_words(_), do: ""
end
