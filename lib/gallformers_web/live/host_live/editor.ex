defmodule GallformersWeb.HostLive.Editor do
  @moduledoc """
  Edit mode's Editorial panel on a plant's page (matter `ec2c`: plant pages
  are editorial): the plant's name, its authorship, its synonyms and its
  range, each edit an editorial item in the curator's tray
  (`Gallformers.Curation`), with what it is "based on" when it departs
  from WCVP. Each is a row of one
  list, its label beside its value and actions (as the Gall page's Edit
  mode sets its rows).

    * **Name:** Rename… gives the new accepted name (the old one stays a
      synonym when it applies, as in the taxonomy admin).
    * **Authorship:** the accepted name's authority (WCVP's authors,
      `Gallformers.Ranges.WcvpAuthorship`, unless a curator changed it);
      Change… gives another, or none.
    * **Synonyms:** each a row with Take out; Add a synonym opens its
      fields: the name, and behind a disclosure the optional "sensu" (for
      a misapplied name) and "based on". The tray holds the whole list the
      plant should have, so the next edit starts from the list in the tray
      (and keeps what it is based on unless a new one is given).
    * **Range:** a summary (its places, how many introduced: the tray's
      range, else the plant's) and Range…, which opens the Host range
      editor on the page (`GallformersWeb.HostLive` runs it); the tray
      holds the whole range.

  What is already in the tray is marked ("in your tray"). The page
  refreshes this component when the tray changes (`send_update/3` with
  `refresh: true`).
  """
  use GallformersWeb, :live_component

  alias Gallformers.{Curation, Ranges}

  @impl true
  def mount(socket),
    do: {:ok, assign(socket, name_dialog: false, authorship_dialog: false, synonym_form: false)}

  @impl true
  def update(%{refresh: true}, socket), do: {:ok, load_pending(socket)}

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(id: assigns.id, host: assigns.host, curator: assigns.curator)
     |> load_pending()}
  end

  defp load_pending(socket) do
    %{curator: curator, host: host} = socket.assigns
    socket = assign(socket, pending: Curation.pending_for(curator, {:plant, host.id}))
    assign(socket, range_summary: range_summary(socket.assigns))
  end

  # The range in a line: its places and how many are introduced, the
  # tray's range when it holds one, else the plant's (as stored: a country
  # is one place).
  defp range_summary(%{pending: pending, host: host}) do
    types =
      case in_tray(pending, :range) do
        nil ->
          host.id
          |> Ranges.get_places_for_taxon_with_precision()
          |> Enum.map(& &1.distribution_type)

        item ->
          Enum.map(item.spec.value, fn {_place_id, _precision, type} -> type end)
      end

    case {length(types), Enum.count(types, &(&1 == "introduced"))} do
      {0, _} -> "No range recorded"
      {places, 0} -> places_word(places)
      {places, introduced} -> "#{places_word(places)}, #{introduced} introduced"
    end
  end

  defp places_word(1), do: "1 place"
  defp places_word(count), do: "#{count} places"

  # The field's item in the tray, if any.
  defp in_tray(pending, field), do: pending |> Map.get({:editorial, field}, []) |> List.first()

  # The synonyms as the tray would leave them: its list, else the plant's.
  defp working_synonyms(%{pending: pending, host: host}) do
    case in_tray(pending, :synonyms) do
      nil -> Enum.map(host.synonyms, &%{name: &1.name, sensu: &1.sensu})
      item -> item.spec.value
    end
  end

  # -- events ----------------------------------------------------------------

  @impl true
  def handle_event("open_name", _params, socket),
    do: {:noreply, assign(socket, name_dialog: true)}

  def handle_event("close_name", _params, socket),
    do: {:noreply, assign(socket, name_dialog: false)}

  def handle_event("rename", %{"name" => name} = params, socket) do
    case String.trim(name) do
      "" ->
        {:noreply, socket}

      name ->
        socket = tray(socket, :name, name, params["based_on"])
        {:noreply, assign(socket, name_dialog: false)}
    end
  end

  def handle_event("open_authorship", _params, socket),
    do: {:noreply, assign(socket, authorship_dialog: true)}

  def handle_event("close_authorship", _params, socket),
    do: {:noreply, assign(socket, authorship_dialog: false)}

  def handle_event("set_authorship", params, socket) do
    socket = tray(socket, :authorship, blank_nil(params["authorship"]), params["based_on"])
    {:noreply, assign(socket, authorship_dialog: false)}
  end

  def handle_event("open_synonym", _params, socket),
    do: {:noreply, assign(socket, synonym_form: true)}

  def handle_event("close_synonym", _params, socket),
    do: {:noreply, assign(socket, synonym_form: false)}

  def handle_event("add_synonym", %{"name" => name} = params, socket) do
    case String.trim(name) do
      "" ->
        {:noreply, socket}

      name ->
        synonym = %{name: name, sensu: blank_nil(params["sensu"])}
        synonyms = Enum.uniq(working_synonyms(socket.assigns) ++ [synonym])

        socket =
          tray(socket, :synonyms, synonyms, blank_nil(params["based_on"]) || based_on(socket))

        {:noreply, assign(socket, synonym_form: false)}
    end
  end

  def handle_event("remove_synonym", %{"name" => name} = params, socket) do
    sensu = blank_nil(params["sensu"])

    synonyms =
      Enum.reject(working_synonyms(socket.assigns), &(&1.name == name and &1.sensu == sensu))

    {:noreply, tray(socket, :synonyms, synonyms, based_on(socket))}
  end

  # A synonym edit keeps what the list in the tray is based on.
  defp based_on(socket) do
    case in_tray(socket.assigns.pending, :synonyms) do
      nil -> nil
      item -> item.spec.based_on
    end
  end

  defp tray(socket, field, value, based_on) do
    spec = %{
      kind: :editorial,
      subject: {:plant, socket.assigns.host.id},
      field: field,
      value: value,
      based_on: blank_nil(based_on) || ""
    }

    case Curation.add_item(socket.assigns.curator, spec) do
      {:ok, _item} ->
        load_pending(socket)

      {:error, reason} ->
        put_flash(socket, :error, "The change couldn't go in your tray (#{reason}).")
    end
  end

  defp blank_nil(value) when value in [nil, ""], do: nil

  defp blank_nil(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: String.trim(value))

  # -- render ----------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        synonyms: working_synonyms(assigns),
        name_item: in_tray(assigns.pending, :name),
        authorship_item: in_tray(assigns.pending, :authorship)
      )

    assigns =
      assign(assigns,
        authorship:
          if(assigns.authorship_item,
            do: assigns.authorship_item.spec.value,
            else: assigns.host.authorship
          )
      )

    ~H"""
    <div id={@id}>
      <%!-- One row per editorial field, label beside its value and actions,
           as the Gall page's Edit mode sets its rows. --%>
      <.panel id="host-editorial" title="Editorial">
        <dl class="flex flex-col divide-y divide-line text-ui">
          <div id="host-editor-name" class="flex flex-wrap items-baseline gap-x-3 gap-y-1 py-1.5">
            <dt class="w-24 shrink-0 text-meta text-muted">Name</dt>
            <dd class="flex min-w-0 flex-1 flex-wrap items-baseline gap-x-3 gap-y-1">
              <span class="min-w-0 flex-1">
                <.taxon_name name={(@name_item && @name_item.spec.value) || @host.name} />
              </span>
              <.tray_mark item={@name_item} />
              <.button variant="ghost" size="sm" phx-click="open_name" phx-target={@myself}>
                Rename…
              </.button>
            </dd>
          </div>

          <div
            id="host-editor-authorship"
            class="flex flex-wrap items-baseline gap-x-3 gap-y-1 py-1.5"
          >
            <dt class="w-24 shrink-0 text-meta text-muted">Authorship</dt>
            <dd class="flex min-w-0 flex-1 flex-wrap items-baseline gap-x-3 gap-y-1">
              <span class={["min-w-0 flex-1", !@authorship && "text-muted"]}>
                {@authorship || "None"}
              </span>
              <.tray_mark item={@authorship_item} />
              <.button variant="ghost" size="sm" phx-click="open_authorship" phx-target={@myself}>
                Change…
              </.button>
            </dd>
          </div>

          <div
            id="host-editor-synonyms"
            class="flex flex-wrap items-baseline gap-x-3 gap-y-1 py-1.5"
          >
            <dt class="w-24 shrink-0 text-meta text-muted">Synonyms</dt>
            <dd class="flex min-w-0 flex-1 flex-col gap-1">
              <ul :if={@synonyms != []} class="flex flex-col">
                <li
                  :for={s <- @synonyms}
                  data-synonym={s.name}
                  class="flex flex-wrap items-baseline gap-x-3"
                >
                  <span class="min-w-0 flex-1">
                    <.taxon_name name={s.name} />
                    <span :if={s.sensu} class="text-meta text-muted">
                      sensu {s.sensu}
                    </span>
                  </span>
                  <.button
                    variant="ghost"
                    size="sm"
                    phx-click="remove_synonym"
                    phx-value-name={s.name}
                    phx-value-sensu={s.sensu || ""}
                    phx-target={@myself}
                    aria-label={"Take out #{s.name}"}
                  >
                    Take out
                  </.button>
                </li>
              </ul>
              <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <span class="min-w-0 flex-1 text-muted">
                  {if @synonyms == [], do: "No synonyms."}
                </span>
                <.tray_mark item={in_tray(@pending, :synonyms)} />
                <.button
                  :if={!@synonym_form}
                  variant="ghost"
                  size="sm"
                  icon="ph-plus"
                  phx-click="open_synonym"
                  phx-target={@myself}
                >
                  Add a synonym
                </.button>
              </div>
              <form
                :if={@synonym_form}
                id="host-synonym-form"
                phx-submit="add_synonym"
                phx-target={@myself}
                class="flex max-w-md flex-col gap-2 py-1"
              >
                <.field label="Synonym" for="host-synonym-name">
                  <input
                    id="host-synonym-name"
                    name="name"
                    type="text"
                    autocomplete="off"
                    class="gf-input"
                    phx-mounted={JS.focus()}
                  />
                </.field>
                <details>
                  <summary class="cursor-pointer text-meta text-link">
                    Sensu and based on (optional)
                  </summary>
                  <div class="mt-2 flex flex-col gap-2">
                    <.field label="Sensu" for="host-synonym-sensu" help="For a misapplied name">
                      <input
                        id="host-synonym-sensu"
                        name="sensu"
                        type="text"
                        autocomplete="off"
                        aria-describedby="host-synonym-sensu-help"
                        class="gf-input"
                      />
                    </.field>
                    <.field
                      label="Based on"
                      for="host-synonym-based-on"
                      help="When it departs from WCVP"
                    >
                      <input
                        id="host-synonym-based-on"
                        name="based_on"
                        type="text"
                        autocomplete="off"
                        aria-describedby="host-synonym-based-on-help"
                        class="gf-input"
                      />
                    </.field>
                  </div>
                </details>
                <div class="flex gap-2">
                  <.button type="submit" size="sm" variant="primary">Put in tray</.button>
                  <.button
                    type="button"
                    size="sm"
                    variant="ghost"
                    phx-click="close_synonym"
                    phx-target={@myself}
                  >
                    Cancel
                  </.button>
                </div>
              </form>
            </dd>
          </div>

          <div id="host-editor-range" class="flex flex-wrap items-baseline gap-x-3 gap-y-1 py-1.5">
            <dt class="w-24 shrink-0 text-meta text-muted">Range</dt>
            <dd class="flex min-w-0 flex-1 flex-wrap items-baseline gap-x-3 gap-y-1">
              <span data-part="summary" class="min-w-0 flex-1">{@range_summary}</span>
              <.tray_mark item={in_tray(@pending, :range)} />
              <.button variant="ghost" size="sm" icon="ph-map-trifold" phx-click="open_range">
                Range…
              </.button>
            </dd>
          </div>
        </dl>
      </.panel>

      <.dialog
        :if={@name_dialog}
        id="host-name-dialog"
        title={"Rename #{@host.name}"}
        size={:sm}
        show
        on_cancel={JS.push("close_name", target: @myself)}
      >
        <form
          id="host-name-form"
          phx-submit="rename"
          phx-target={@myself}
          class="flex flex-col gap-block"
        >
          <.field label="New name" for="host-new-name" help="The old name stays a synonym.">
            <input
              id="host-new-name"
              name="name"
              type="text"
              value={(@name_item && @name_item.spec.value) || @host.name}
              class="gf-input"
            />
          </.field>
          <.field label="Based on" for="host-name-based-on" help="When it departs from WCVP">
            <input
              id="host-name-based-on"
              name="based_on"
              type="text"
              value={@name_item && @name_item.spec.based_on}
              class="gf-input"
            />
          </.field>
        </form>
        <:actions>
          <.button type="button" variant="ghost" phx-click="close_name" phx-target={@myself}>
            Cancel
          </.button>
          <.button type="submit" form="host-name-form" variant="primary">Put in tray</.button>
        </:actions>
      </.dialog>

      <.dialog
        :if={@authorship_dialog}
        id="host-authorship-dialog"
        title={"Authorship of #{@host.name}"}
        size={:sm}
        show
        on_cancel={JS.push("close_authorship", target: @myself)}
      >
        <form
          id="host-authorship-form"
          phx-submit="set_authorship"
          phx-target={@myself}
          class="flex flex-col gap-block"
        >
          <.field label="Authorship" for="host-authorship" help="Blank for none.">
            <input
              id="host-authorship"
              name="authorship"
              type="text"
              value={@authorship}
              placeholder="(L.) Sm."
              aria-describedby="host-authorship-help"
              class="gf-input"
            />
          </.field>
          <.field label="Based on" for="host-authorship-based-on" help="When it departs from WCVP">
            <input
              id="host-authorship-based-on"
              name="based_on"
              type="text"
              value={@authorship_item && @authorship_item.spec.based_on}
              aria-describedby="host-authorship-based-on-help"
              class="gf-input"
            />
          </.field>
        </form>
        <:actions>
          <.button type="button" variant="ghost" phx-click="close_authorship" phx-target={@myself}>
            Cancel
          </.button>
          <.button type="submit" form="host-authorship-form" variant="primary">
            Put in tray
          </.button>
        </:actions>
      </.dialog>
    </div>
    """
  end

  attr :item, :any, default: nil

  defp tray_mark(assigns) do
    ~H"""
    <span :if={@item} data-part="pending" title={@item.text}>
      <.chip variant={:info} size="sm">in your tray</.chip>
    </span>
    """
  end
end
