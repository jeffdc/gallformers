defmodule GallformersWeb.HostLive.Editor do
  @moduledoc """
  Edit mode's Editorial panel on a plant's page (matter `ec2c`: plant pages
  are editorial): the plant's name, its synonyms and its range, each edit
  an editorial item in the curator's tray (`Gallformers.Curation`), with
  what it is "based on" when it departs from WCVP.

    * **Name:** Rename… gives the new accepted name (the old one stays a
      synonym when it applies, as in the taxonomy admin).
    * **Synonyms:** each taken out with ✕, one added by name (and "sensu"
      for a misapplied name). The tray holds the whole list the plant
      should have, so the next edit starts from the list in the tray.
    * **Range:** Range… opens the Host range editor on the page
      (`GallformersWeb.HostLive` runs it); the tray holds the whole range.

  What is already in the tray is marked ("in your tray"). The page
  refreshes this component when the tray changes (`send_update/3` with
  `refresh: true`).
  """
  use GallformersWeb, :live_component

  alias Gallformers.Curation

  @impl true
  def mount(socket), do: {:ok, assign(socket, name_dialog: false)}

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
    assign(socket, pending: Curation.pending_for(curator, {:plant, host.id}))
  end

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

  def handle_event("add_synonym", %{"name" => name} = params, socket) do
    case String.trim(name) do
      "" ->
        {:noreply, socket}

      name ->
        synonym = %{name: name, sensu: blank_nil(params["sensu"])}
        synonyms = Enum.uniq(working_synonyms(socket.assigns) ++ [synonym])
        {:noreply, tray(socket, :synonyms, synonyms, params["based_on"] || based_on(socket))}
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
        name_item: in_tray(assigns.pending, :name)
      )

    ~H"""
    <div id={@id}>
      <.panel id="host-editorial" title="Editorial">
        <div class="flex flex-col gap-block text-ui">
          <div id="host-editor-name" class="flex flex-col gap-1">
            <span class="gf-label">Name</span>
            <div class="flex flex-wrap items-center gap-2">
              <.taxon_name name={(@name_item && @name_item.spec.value) || @host.name} />
              <.button size="sm" variant="secondary" phx-click="open_name" phx-target={@myself}>
                Rename…
              </.button>
              <.tray_mark item={@name_item} />
            </div>
          </div>

          <div id="host-editor-synonyms" class="flex flex-col gap-1">
            <span class="gf-label">Synonyms</span>
            <ul :if={@synonyms != []} class="flex flex-wrap gap-1.5">
              <li :for={s <- @synonyms}>
                <.chip
                  variant={:neutral}
                  on_remove={
                    JS.push("remove_synonym",
                      value: %{name: s.name, sensu: s.sensu || ""},
                      target: @myself
                    )
                  }
                  remove_label={"Take out #{s.name}"}
                  data-synonym={s.name}
                >
                  <i>{s.name}</i><span :if={s.sensu}> sensu {s.sensu}</span>
                </.chip>
              </li>
            </ul>
            <p :if={@synonyms == []} class="text-muted">No synonyms. Add one below.</p>
            <.tray_mark item={in_tray(@pending, :synonyms)} />
            <form
              phx-submit="add_synonym"
              phx-target={@myself}
              class="mt-1 flex flex-wrap items-end gap-2"
            >
              <.field label="Add a synonym" for="host-synonym-name">
                <input id="host-synonym-name" name="name" type="text" class="gf-input" />
              </.field>
              <.field label="Sensu" for="host-synonym-sensu" help="For a misapplied name">
                <input id="host-synonym-sensu" name="sensu" type="text" class="gf-input" />
              </.field>
              <.field label="Based on" for="host-synonym-based-on" help="When it departs from WCVP">
                <input id="host-synonym-based-on" name="based_on" type="text" class="gf-input" />
              </.field>
              <.button type="submit" size="sm" variant="secondary">Add</.button>
            </form>
          </div>

          <div id="host-editor-range" class="flex flex-col gap-1">
            <span class="gf-label">Range</span>
            <div class="flex flex-wrap items-center gap-2">
              <.button size="sm" variant="secondary" icon="ph-map-trifold" phx-click="open_range">
                Range…
              </.button>
              <.tray_mark item={in_tray(@pending, :range)} />
            </div>
          </div>
        </div>
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
