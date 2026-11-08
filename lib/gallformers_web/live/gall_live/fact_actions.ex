defmodule GallformersWeb.GallLive.FactActions do
  @moduledoc """
  The Fact inspector in Edit mode on the Gall page (matter `87a1`, task 7):
  the `fact_inspector` with Gallformers' actions in its Gallformers block,
  and a new Fact's form for a group's Add. Every action goes into the
  curator's tray as a Gallformers change (`Gallformers.Curation`):

    * Confirm… (when Gallformers hasn't stated the Fact) adds it, Deny…
      withdraws it, Change… corrects it to another value (the shared plant
      search for a Host, the Trait's values, the place search, a common
      name written in), Add a note… is a note on the Fact;
    * a new Fact (Add a host, + a Trait value, Add a place, Add a common
      name) adds it.

  Each takes a Why (`Gallformers.Curation.evidence_from_why/1`: its words,
  and the observation links in them as the statement's Observations). The
  Inducer has a note only: its taxonomy is edited on its own page. While
  the Fact has a change in the tray, the block says so, with Take out.

  The page (`GallformersWeb.GallLive`) gives the Fact (or the group being
  added to), the Gall, the curator and the tray's items for the Fact; it
  hears `{#{inspect(__MODULE__)}, :added}` once something went into the tray.
  """
  use GallformersWeb, :live_component

  import GallformersWeb.FactsComponents, only: [fact_inspector: 1, trait_label: 1]
  import GallformersWeb.ReviewComponents, only: [review_value_list: 1]

  alias Gallformers.Catalog
  alias Gallformers.Curation
  alias GallformersWeb.Choices
  alias GallformersWeb.TaxonomyURL

  @results 8

  @impl true
  def mount(socket) do
    {:ok, assign(socket, definitions: Catalog.trait_definitions()) |> reset()}
  end

  @impl true
  def update(assigns, socket) do
    changed? =
      Map.get(assigns, :fact) != socket.assigns[:fact] or
        Map.get(assigns, :new) != socket.assigns[:new]

    socket = assign(socket, Map.take(assigns, [:id, :fact, :new, :gall, :curator, :pending]))
    socket = assign(socket, fact: assigns[:fact], new: assigns[:new])

    {:ok, if(changed?, do: reset(socket), else: socket)}
  end

  defp reset(socket) do
    assign(socket,
      action: nil,
      error: nil,
      plant: nil,
      plant_query: "",
      plant_results: [],
      place: nil,
      place_query: "",
      place_results: [],
      values: []
    )
  end

  # -- events --------------------------------------------------------------------------

  @impl true
  def handle_event("act", %{"action" => action}, socket)
      when action in ~w(confirm correct withdraw note),
      do: {:noreply, socket |> reset() |> assign(action: action)}

  def handle_event("cancel", _params, socket), do: {:noreply, reset(socket)}

  def handle_event("search_plant", %{"value" => query}, socket),
    do:
      {:noreply,
       assign(socket, plant_query: query, plant_results: Choices.hosts(query, @results))}

  def handle_event("select_plant", %{"id" => id}, socket) do
    plant = Enum.find(socket.assigns.plant_results, &(to_string(&1.id) == id))
    {:noreply, assign(socket, plant: plant, plant_query: "", plant_results: [], error: nil)}
  end

  def handle_event("clear_plant", _params, socket),
    do: {:noreply, assign(socket, plant: nil, plant_query: "", plant_results: [])}

  def handle_event("search_place", %{"value" => query}, socket) do
    results = Choices.places(query, place_kind(socket.assigns), @results)
    {:noreply, assign(socket, place_query: query, place_results: results)}
  end

  def handle_event("select_place", %{"id" => id}, socket) do
    place = Enum.find(socket.assigns.place_results, &(to_string(&1.id) == id))
    {:noreply, assign(socket, place: place, place_query: "", place_results: [], error: nil)}
  end

  def handle_event("clear_place", _params, socket),
    do: {:noreply, assign(socket, place: nil, place_query: "", place_results: [])}

  def handle_event("pick_value", %{"value" => value}, socket) do
    values =
      cond do
        socket.assigns.action == "correct" -> [value]
        value in socket.assigns.values -> List.delete(socket.assigns.values, value)
        true -> socket.assigns.values ++ [value]
      end

    {:noreply, assign(socket, values: values, error: nil)}
  end

  def handle_event("take_out", %{"id" => id}, socket) do
    _ = Curation.remove_item(socket.assigns.curator, String.to_integer(id))
    {:noreply, socket}
  end

  def handle_event("submit", params, socket) do
    case specs(socket.assigns, params) do
      {:ok, specs} -> {:noreply, add(socket, specs, params["why"])}
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  # -- what an action puts in the tray ---------------------------------------------------

  defp specs(%{action: "note", fact: fact} = assigns, %{"why" => why}) do
    case String.trim(why || "") do
      "" -> {:error, "Write the note."}
      text -> {:ok, [%{kind: :note, gall_id: assigns.gall.id, key: fact.key, text: text}]}
    end
  end

  defp specs(%{action: "confirm", fact: fact} = assigns, _params),
    do: {:ok, [fact_spec(assigns, :add, fact.key)]}

  defp specs(%{action: "withdraw", fact: fact} = assigns, _params),
    do: {:ok, [fact_spec(assigns, :withdraw, fact.key)]}

  defp specs(%{action: "correct", fact: fact} = assigns, params) do
    case new_keys(change_group(fact), assigns, params, :change) do
      {:ok, [to]} -> {:ok, [Map.put(fact_spec(assigns, :correct, fact.key), :to, to)]}
      {:ok, _} -> {:error, "Choose one value."}
      error -> error
    end
  end

  defp specs(%{new: group} = assigns, params) when is_binary(group) do
    with {:ok, keys} <- new_keys(group, assigns, params, :add),
         do: {:ok, Enum.map(keys, &fact_spec(assigns, :add, &1))}
  end

  defp specs(_assigns, _params), do: {:error, "Choose what to do."}

  defp fact_spec(assigns, action, key),
    do: %{kind: :fact, gall_id: assigns.gall.id, action: action, key: key}

  # The keys the form names, for a group.
  defp new_keys("host", %{plant: nil}, _params, mode),
    do:
      {:error,
       if(mode == :change, do: "Choose the plant it should be.", else: "Choose the plant.")}

  defp new_keys("host", %{plant: plant}, _params, _mode), do: {:ok, [{:host, plant.id}]}

  defp new_keys("trait:" <> _trait, %{values: []}, _params, _mode),
    do: {:error, "Choose a value."}

  defp new_keys("trait:" <> trait, %{values: values}, _params, _mode),
    do: {:ok, Enum.map(values, &{:trait, trait, &1})}

  defp new_keys("alias", _assigns, params, _mode) do
    case String.trim(params["value"] || "") do
      "" -> {:error, "Write the common name."}
      name -> {:ok, [{:alias, name}]}
    end
  end

  defp new_keys("range", %{place: nil}, _params, _mode), do: {:error, "Choose the place."}

  defp new_keys("range", %{place: place} = assigns, params, _mode) do
    case adjustment(assigns, params) do
      :occurrence -> {:ok, [{:occurrence, place.id}]}
      adjustment when adjustment in [:exclude, :only] -> {:ok, [{:range, adjustment, place.id}]}
      _ -> {:error, "Choose what the place is: not in, only in, or recorded in."}
    end
  end

  defp new_keys(_group, _assigns, _params, _mode), do: {:error, "Choose what to do."}

  # A change keeps the Fact's kind of place; a new place says which.
  defp adjustment(%{action: "correct", fact: %{kind: :occurrence}}, _params), do: :occurrence

  defp adjustment(%{action: "correct", fact: %{value: %{adjustment: adjustment}}}, _params),
    do: adjustment

  defp adjustment(_assigns, %{"adjustment" => "occurrence"}), do: :occurrence
  defp adjustment(_assigns, %{"adjustment" => "exclude"}), do: :exclude
  defp adjustment(_assigns, %{"adjustment" => "only"}), do: :only
  defp adjustment(_assigns, _params), do: nil

  defp change_group(%{kind: :host}), do: "host"
  defp change_group(%{kind: :trait, trait: trait}), do: "trait:" <> trait
  defp change_group(%{kind: :alias}), do: "alias"
  defp change_group(%{kind: kind}) when kind in [:range, :occurrence], do: "range"
  defp change_group(_fact), do: nil

  defp place_kind(%{action: "correct", fact: %{kind: :occurrence}}), do: :occurrence
  defp place_kind(%{action: "correct"}), do: :range
  defp place_kind(_assigns), do: :range

  # Each spec into the tray, with the Why as its own evidence (a note's
  # words are the note).
  defp add(socket, specs, why) do
    %{curator: curator} = socket.assigns
    evidence = Curation.evidence_from_why(why)

    result =
      Enum.reduce_while(specs, :ok, fn spec, :ok ->
        with {:ok, item} <- Curation.add_item(curator, spec),
             :ok <- evidence(curator, item, spec, evidence) do
          {:cont, :ok}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      :ok ->
        send(self(), {__MODULE__, :added})
        reset(socket)

      {:error, reason} ->
        assign(socket, error: "It couldn't go in your tray (#{reason}).")
    end
  end

  defp evidence(_curator, _item, %{kind: :note}, _evidence), do: :ok
  defp evidence(_curator, _item, _spec, nil), do: :ok

  defp evidence(curator, item, _spec, evidence) do
    case Curation.set_item_evidence(curator, item.id, evidence) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # -- the inspector ------------------------------------------------------------------

  @impl true
  def render(%{new: group} = assigns) when is_binary(group) do
    assigns = assign(assigns, group: group)

    ~H"""
    <div id={@id}>
      <.fact_inspector
        id="fact-inspector"
        state={:new}
        new={new_title(@group)}
        of={@gall}
        editing
        on_close="close_fact"
      >
        <p class="mb-3 text-meta text-ink-2">
          Your statement is Gallformers', dated when you apply it. Say what it rests on: an observation's link, or why.
        </p>
        <.action_form group={@group} mode={:add} {assigns} />
      </.fact_inspector>
    </div>
    """
  end

  def render(assigns) do
    assigns = assign(assigns, inducer?: assigns.fact.kind == :inducer)

    ~H"""
    <div id={@id}>
      <.fact_inspector
        id="fact-inspector"
        fact={@fact}
        of={@gall}
        editing
        on_close="close_fact"
      >
        <:actions>
          <div :if={@pending != []} data-part="pending" class="flex flex-col gap-1">
            <p
              :for={item <- @pending}
              class="flex flex-wrap items-baseline gap-2 text-meta text-ink-2"
            >
              <span>In your tray: {item.text}</span>
              <.button
                size="sm"
                variant="link"
                phx-click="take_out"
                phx-value-id={item.id}
                phx-target={@myself}
              >
                Take out
              </.button>
            </p>
          </div>

          <div :if={@pending == [] and @action == nil} class="flex flex-wrap gap-2">
            <%= if @inducer? do %>
              <.button size="sm" phx-click="act" phx-value-action="note" phx-target={@myself}>
                Add a note…
              </.button>
              <p class="w-full text-meta text-muted">
                The Inducer is taxonomy: <.link navigate={
                  TaxonomyURL.inducer_path(@fact.value.subject, edit: true)
                }>
                  edit it on its page
                </.link>.
              </p>
            <% else %>
              <.button
                :if={@fact.gallformers == nil}
                size="sm"
                phx-click="act"
                phx-value-action="confirm"
                phx-target={@myself}
              >
                Confirm…
              </.button>
              <.button size="sm" phx-click="act" phx-value-action="correct" phx-target={@myself}>
                Change…
              </.button>
              <.button size="sm" phx-click="act" phx-value-action="withdraw" phx-target={@myself}>
                Deny…
              </.button>
              <.button
                size="sm"
                variant="ghost"
                phx-click="act"
                phx-value-action="note"
                phx-target={@myself}
              >
                Add a note…
              </.button>
            <% end %>
          </div>

          <div :if={@action} class="rounded-panel bg-surface-2 p-panel">
            <p class="mb-2 text-meta text-ink-2">{action_words(@action)}</p>
            <.action_form group={change_group(@fact)} mode={mode(@action)} {assigns} />
          </div>
        </:actions>
      </.fact_inspector>
    </div>
    """
  end

  defp mode("correct"), do: :change
  defp mode("note"), do: :note
  defp mode(_action), do: :plain

  attr :group, :string, default: nil
  attr :mode, :atom, required: true
  attr :myself, :any, required: true
  attr :error, :string, default: nil
  attr :plant, :map, default: nil
  attr :plant_query, :string, default: ""
  attr :plant_results, :list, default: []
  attr :place, :map, default: nil
  attr :place_query, :string, default: ""
  attr :place_results, :list, default: []
  attr :values, :list, default: []
  attr :definitions, :map, default: %{}
  attr :action, :any, default: nil
  attr :fact, :map, default: nil
  attr :rest, :global

  # The short form an action or a new Fact opens: the value where it has
  # one, then Why, then Add to tray and Cancel.
  defp action_form(assigns) do
    assigns = assign(assigns, value?: assigns.mode in [:change, :add])

    ~H"""
    <form id="fact-action-form" phx-submit="submit" phx-target={@myself} class="flex flex-col gap-3">
      <.typeahead
        :if={@value? and @group == "host"}
        id="fact-action-plant"
        label={if @mode == :change, do: "Change it to", else: "The plant"}
        placeholder="A plant's name: species, genus or section"
        query={@plant_query}
        results={@plant_results}
        selected={@plant}
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

      <div :if={@value? and match?("trait:" <> _, @group)} class="flex flex-col gap-1">
        <span class="text-meta font-semibold text-ink-2">
          {if @mode == :change, do: "Change it to", else: "Its values"}
        </span>
        <.review_value_list
          id="fact-action-values"
          type={if @mode == :change, do: "radio", else: "checkbox"}
          values={trait_values(@definitions, @group)}
          selected={@values}
          on_pick="pick_value"
          target={@myself}
        />
      </div>

      <.input
        :if={@value? and @group == "alias"}
        type="text"
        name="value"
        value=""
        label={if @mode == :change, do: "Change it to", else: "The common name"}
      />

      <.input
        :if={@mode == :add and @group == "range"}
        type="select"
        name="adjustment"
        value="occurrence"
        label="The place is"
        options={[
          {"where the Gall was recorded", "occurrence"},
          {"not in its range", "exclude"},
          {"the only place in its range", "only"}
        ]}
      />
      <.typeahead
        :if={@value? and @group == "range"}
        id="fact-action-place"
        label={if @mode == :change, do: "Change it to", else: "The place"}
        placeholder="A state, province or country"
        query={@place_query}
        results={@place_results}
        selected={@place}
        search_event="search_place"
        select_event="select_place"
        clear_event="clear_place"
        display_fn={&place_words/1}
        group_key={:group}
        target={@myself}
      >
        <:result :let={place}>{place_words(place)}</:result>
      </.typeahead>

      <.input
        type="textarea"
        name="why"
        value=""
        label={if @mode == :note, do: "Note", else: "Why (an observation's link, a paper, a reason)"}
      />

      <p :if={@error} id="fact-action-error" class="text-meta text-danger">{@error}</p>

      <div class="flex gap-2">
        <.button type="submit" variant="primary" size="sm">Add to tray</.button>
        <.button type="button" size="sm" variant="ghost" phx-click="cancel" phx-target={@myself}>
          Cancel
        </.button>
      </div>
    </form>
    """
  end

  defp trait_values(definitions, "trait:" <> trait),
    do: definitions |> Map.get(trait, %{}) |> Enum.sort()

  defp place_words(%{name: name, meta: nil}), do: name
  defp place_words(%{name: name, meta: parent}), do: "#{name} — #{parent}"

  defp action_words("confirm"),
    do: "Gallformers states it too, dated when you apply it: say what it rests on."

  defp action_words("correct"), do: "Gallformers states another value, dated when you apply it."

  defp action_words("withdraw"),
    do:
      "Gallformers says it isn't so, dated when you apply it. The other Sources' statements stay."

  defp action_words("note"), do: "A note on this Fact, from Gallformers. It changes nothing."

  defp new_title("host"), do: "Host"
  defp new_title("range"), do: "place"
  defp new_title("alias"), do: "common name"
  defp new_title("trait:" <> trait), do: trait_label(trait)
end
