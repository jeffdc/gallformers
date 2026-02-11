defmodule GallformersWeb.Admin.KeyLive.Form do
  @moduledoc """
  Admin form for creating and editing identification keys.

  Supports two input methods:
  - File upload via dropzone that populates the JSON textarea
  - Direct JSON paste/edit in the textarea

  When valid JSON is entered, metadata fields (title, subtitle, etc.) are
  auto-populated from the JSON but can be manually overridden.
  """
  use GallformersWeb, :live_view
  use GallformersWeb.Admin.FormHelpers, crud_helpers: true

  import GallformersWeb.Admin.FormComponents, only: [form_actions: 1]

  alias Gallformers.Keys
  alias Gallformers.Keys.Key

  # Required callbacks for FormHelpers
  @impl GallformersWeb.Admin.FormHelpers
  def entity_key, do: :key
  @impl GallformersWeb.Admin.FormHelpers
  def entity_struct, do: Key
  @impl GallformersWeb.Admin.FormHelpers
  def list_path, do: ~p"/admin/keys"
  @impl GallformersWeb.Admin.FormHelpers
  def load_entity(id), do: Keys.get_key!(id)
  @impl GallformersWeb.Admin.FormHelpers
  def change_entity(entity, params \\ %{}), do: Keys.change_key(entity, params)
  @impl GallformersWeb.Admin.FormHelpers
  def create_entity(params), do: Keys.create_key(params)
  @impl GallformersWeb.Admin.FormHelpers
  def update_entity(entity, params), do: Keys.update_key(entity, params)
  @impl GallformersWeb.Admin.FormHelpers
  def delete_entity(entity), do: Keys.delete_key(entity)

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> init_admin_form(session, page_title: "Key")
      |> assign(:json_input, "")
      |> assign(:json_error, nil)
      |> assign(:couplet_count, nil)
      |> allow_upload(:key_json,
        accept: ~w(.json),
        max_entries: 1,
        auto_upload: true,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  def close_form(socket) do
    push_navigate(socket, to: list_path())
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    apply_new_action(socket)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket = apply_edit_action(socket, id)

    if socket.assigns[:key] do
      key = socket.assigns.key
      json = Jason.encode!(to_json_map(key), pretty: true)

      socket
      |> assign(:json_input, json)
      |> assign(:couplet_count, map_size(key.couplets))
    else
      socket
    end
  end

  @impl true
  def handle_event("validate", params, socket) do
    handle_validate(params, socket)
  end

  @impl true
  def handle_event("save", params, socket) do
    key_params = Map.get(params, "key", %{})

    # Merge couplets from JSON input into params
    key_params =
      case parse_json_couplets(socket.assigns.json_input) do
        {:ok, couplets_json} -> Map.put(key_params, "couplets", couplets_json)
        _ -> key_params
      end

    handle_save(%{"key" => key_params}, socket)
  end

  @impl true
  def handle_event("delete", params, socket), do: handle_delete(params, socket)

  @impl true
  def handle_event("json_changed", %{"value" => json_text}, socket) do
    socket = assign(socket, :json_input, json_text)

    case Jason.decode(json_text) do
      {:ok, data} when is_map(data) ->
        couplets = data["couplets"] || %{}
        couplet_count = map_size(couplets)

        # Auto-populate metadata from JSON
        key = Map.get(socket.assigns, :key, %Key{})

        meta_params =
          %{}
          |> maybe_put("title", data["title"])
          |> maybe_put("subtitle", data["subtitle"])
          |> maybe_put("authors", Jason.encode!(data["authors"] || []))
          |> maybe_put("citation", data["citation"])
          |> maybe_put("citation_url", data["citation_url"])
          |> maybe_put("description", data["description"])
          |> maybe_put("version", data["version"])
          |> maybe_put("slug", data["slug"])

        changeset =
          key
          |> Keys.change_key(meta_params)
          |> Map.put(:action, :validate)

        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: "key"))
         |> assign(:json_error, nil)
         |> assign(:couplet_count, couplet_count)
         |> mark_dirty()}

      {:ok, _} ->
        {:noreply, assign(socket, json_error: "JSON must be an object", couplet_count: nil)}

      {:error, %Jason.DecodeError{} = err} ->
        {:noreply,
         assign(socket, json_error: "Invalid JSON: #{Exception.message(err)}", couplet_count: nil)}
    end
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(request_cancel cancel_discard confirm_discard) do
    handle_form_event(event, params, socket)
  end

  # Handle file upload completion
  defp handle_progress(:key_json, entry, socket) do
    if entry.done? do
      json_text =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, File.read!(path)}
        end)

      # Trigger the same parsing as manual JSON input
      send(self(), {:file_uploaded, json_text})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:file_uploaded, json_text}, socket) do
    # Reuse the json_changed handler logic
    {:noreply, socket} = handle_event("json_changed", %{"value" => json_text}, socket)
    {:noreply, socket}
  end

  defp parse_json_couplets(json_text) do
    case Jason.decode(json_text) do
      {:ok, data} when is_map(data) ->
        couplets = data["couplets"]

        if is_map(couplets) and map_size(couplets) > 0 do
          {:ok, Jason.encode!(couplets)}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Convert a Key struct back to the JSON format for editing
  defp to_json_map(key) do
    %{
      "slug" => key.slug,
      "title" => key.title,
      "subtitle" => key.subtitle,
      "authors" => key.authors || [],
      "citation" => key.citation,
      "citation_url" => key.citation_url,
      "description" => key.description,
      "version" => key.version,
      "couplets" => to_json_couplets(key.couplets)
    }
  end

  defp to_json_couplets(couplets) when is_map(couplets) do
    Map.new(couplets, fn {number, couplet} ->
      {number,
       %{
         "leads" =>
           Enum.map(couplet.leads, fn lead ->
             %{
               "text" => lead.text,
               "notes" => lead[:notes],
               "images" => Enum.map(lead.images || [], &to_json_image/1),
               "destination" => to_json_destination(lead.destination)
             }
           end)
       }}
    end)
  end

  defp to_json_image(image) do
    %{"ref" => image[:ref], "file" => image[:file], "caption" => image[:caption]}
  end

  defp to_json_destination(nil), do: nil

  defp to_json_destination(dest) do
    base = %{"type" => dest.type}

    case dest.type do
      "couplet" ->
        base
        |> Map.put("number", dest[:number])
        |> Map.put("label", dest[:label])

      "taxon" ->
        species_ids = dest[:species_ids] || []

        species_id =
          case species_ids do
            [single] -> single
            ids when is_list(ids) and ids != [] -> ids
            _ -> nil
          end

        base
        |> Map.put("name", dest[:name])
        |> Map.put("context", dest[:context])
        |> Map.put("species_id", species_id)

      _ ->
        base
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_user={@current_user}
      page_title={@page_title}
      public_url={if @mode == :edit, do: ~p"/keys/#{@key.slug}"}
    >
      <Layouts.admin_edit_layout
        back_path={~p"/admin/keys"}
        back_label="Back to Keys"
        title={if @mode == :new, do: "New Identification Key", else: "Edit Identification Key"}
      >
        <:intro>
          Upload a key JSON file or paste JSON directly. Metadata fields will be auto-populated from the JSON.
        </:intro>

        <.form for={@form} id="key-form" phx-change="validate" phx-submit="save">
          <%!-- JSON Input Section --%>
          <div class="mb-6 p-4 bg-gray-50 rounded-lg border border-gray-200">
            <h3 class="text-lg font-semibold text-gray-700 mb-3">Key Data (JSON)</h3>

            <%!-- File Upload --%>
            <div class="mb-3">
              <label class="block text-sm font-medium text-gray-700 mb-1">Upload JSON file</label>
              <.live_file_input
                upload={@uploads.key_json}
                class="block w-full text-sm text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded-md file:border-0 file:text-sm file:font-semibold file:bg-gf-maroon file:text-white hover:file:bg-gf-maroon/90"
              />
            </div>

            <%!-- JSON Textarea --%>
            <div class="mb-2">
              <label class="block text-sm font-medium text-gray-700 mb-1">
                JSON content
                <span :if={@couplet_count} class="text-gray-500 font-normal">
                  — {@couplet_count} couplet(s)
                </span>
              </label>
              <textarea
                id="json-input"
                name="json_input"
                phx-hook="InputEvent"
                data-event="json_changed"
                rows="12"
                class={[
                  "w-full rounded-md border font-mono text-sm p-3",
                  if(@json_error, do: "border-red-300 bg-red-50", else: "border-gray-300")
                ]}
                phx-debounce="500"
              >{@json_input}</textarea>
              <p :if={@json_error} class="mt-1 text-sm text-red-600">{@json_error}</p>
            </div>
          </div>

          <%!-- Metadata Fields --%>
          <div class="space-y-3">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <.input field={@form[:title]} schema={Key} type="text" label="Title" />
              <.input field={@form[:subtitle]} type="text" label="Subtitle" />
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <.input
                field={@form[:slug]}
                type="text"
                label="Slug"
                placeholder="Auto-generated from title"
              />
              <.input
                field={@form[:version]}
                schema={Key}
                type="text"
                label="Version"
                placeholder="e.g. 2026-02-10"
              />
            </div>

            <.input field={@form[:description]} type="textarea" label="Description" rows="3" />

            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <.input field={@form[:citation]} type="text" label="Citation" />
              <.input field={@form[:citation_url]} type="text" label="Citation URL" />
            </div>
          </div>

          <div class="flex justify-between pt-4 mt-4 border-t border-gray-200">
            <div>
              <button
                :if={@mode == :edit}
                type="button"
                phx-click="delete"
                data-confirm="Are you sure you want to delete this key? This cannot be undone."
                class="gf-btn gf-btn-danger"
              >
                Delete
              </button>
            </div>
            <.form_actions form_dirty={@form_dirty} mode={@mode} create_label="Create Key" />
          </div>
        </.form>

        <.discard_confirm_modal show={@show_discard_confirm} />
      </Layouts.admin_edit_layout>
    </Layouts.admin>
    """
  end
end
