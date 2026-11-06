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

  require Logger

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

  @impl GallformersWeb.Admin.FormHelpers
  def after_create(socket, entity) do
    trigger_pdf_generation(entity)

    socket
    |> put_flash(:info, "Key created successfully. PDF generation started.")
    |> push_navigate(to: "#{list_path()}/#{entity.id}")
  end

  @impl GallformersWeb.Admin.FormHelpers
  def after_update(socket, entity) do
    trigger_pdf_generation(entity)

    changeset = change_entity(entity)

    socket
    |> put_flash(:info, "Key updated successfully. PDF generation started.")
    |> assign(entity_key(), entity)
    |> assign(:form, to_form(changeset, as: "key"))
    |> assign(:form_dirty, false)
  end

  defp trigger_pdf_generation(key) do
    Gallformers.Async.run(fn ->
      case Keys.generate_and_upload(key) do
        :ok ->
          Logger.info("PDF generated and uploaded for key: #{key.slug}")

        {:error, reason} ->
          Logger.error("PDF generation failed for key #{key.slug}: #{inspect(reason)}")
      end
    end)
  end

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> init_admin_form(session, page_title: "Key")
      |> assign(:json_input, "")
      |> assign(:json_error, nil)
      |> assign(:couplet_count, nil)
      |> assign(:show_delete_modal, false)
      |> assign(:delete_confirmation, "")
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
    key_params =
      params
      |> Map.get("key", %{})
      |> merge_json_only_fields(socket.assigns.json_input)

    handle_save(%{"key" => key_params}, socket)
  end

  @impl true
  def handle_event("delete", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_modal, true)
     |> assign(:delete_confirmation, "")}
  end

  @impl true
  def handle_event("update_delete_confirmation", %{"value" => value}, socket) do
    {:noreply, assign(socket, :delete_confirmation, value)}
  end

  @impl true
  def handle_event("confirm_delete", %{"confirmation" => confirmation}, socket) do
    selected_key = socket.assigns.key

    case selected_key && Keys.get_key_by_id(selected_key.id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:info, "Key already deleted")
         |> push_navigate(to: list_path())}

      key when confirmation != key.title ->
        {:noreply, put_flash(socket, :error, "Title does not match. Type the exact key title.")}

      key ->
        handle_delete(%{}, assign(socket, :key, key))
    end
  end

  @impl true
  def handle_event("cancel_delete", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_modal, false)
     |> assign(:delete_confirmation, "")}
  end

  @impl true
  def handle_event("regenerate_pdfs", _params, socket) do
    key = socket.assigns.key
    trigger_pdf_generation(key)
    {:noreply, put_flash(socket, :info, "PDF regeneration started for #{key.title}")}
  end

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

  # Content image manager notifications (component manages its own state)
  @impl true
  def handle_info({:image_uploaded, _image}, socket), do: {:noreply, socket}
  def handle_info({:image_deleted, _id}, socket), do: {:noreply, socket}
  def handle_info({:images_reordered, _order}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:file_uploaded, json_text}, socket) do
    # Reuse the json_changed handler logic
    {:noreply, socket} = handle_event("json_changed", %{"value" => json_text}, socket)
    {:noreply, socket}
  end

  # `couplets` and `authors` have no inputs of their own in the form, so the
  # browser never posts them. Both are merged in from the JSON textarea on save,
  # otherwise the changeset never casts them and the stored values go stale.
  defp merge_json_only_fields(key_params, json_text) do
    case Jason.decode(json_text) do
      {:ok, data} when is_map(data) ->
        key_params =
          case data["couplets"] do
            c when is_map(c) and map_size(c) > 0 ->
              Map.put(key_params, "couplets", Jason.encode!(c))

            _ ->
              key_params
          end

        Map.put(key_params, "authors", Jason.encode!(data["authors"] || []))

      _ ->
        key_params
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
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:crumb navigate={~p"/admin/keys"}>Keys</:crumb>
          <:title>{if @mode == :edit, do: @key.title, else: "New key"}</:title>
          <:meta :if={@mode == :edit} label="Version">{@key.version}</:meta>
          <:meta :if={@mode == :edit} label="Couplets">{map_size(@key.couplets || %{})}</:meta>
          <:description>
            Upload the key's JSON file or paste its JSON. The fields below are filled from it.
          </:description>
          <:action :if={@mode == :edit}>
            <.button
              href={~p"/keys/#{@key.slug}"}
              target="_blank"
              variant="ghost"
              size="sm"
              icon="ph-arrow-square-out"
            >
              View on site
            </.button>
          </:action>
        </.page_header>

        <div class="gf-with-rail">
          <div class="flex max-w-form min-w-0 flex-col gap-section">
            <.form
              for={@form}
              id="key-form"
              phx-change="validate"
              phx-submit="save"
              class="flex flex-col gap-section"
            >
              <.section title="The key (JSON)">
                <div class="flex flex-col gap-block">
                  <div>
                    <label class="gf-label" for={@uploads.key_json.ref}>Upload a JSON file</label>
                    <.live_file_input upload={@uploads.key_json} class="gf-file" />
                  </div>
                  <div>
                    <label class="gf-label" for="json-input">
                      JSON
                      <span :if={@couplet_count} class="font-normal text-muted">
                        · {@couplet_count} {if @couplet_count == 1, do: "couplet", else: "couplets"}
                      </span>
                    </label>
                    <textarea
                      id="json-input"
                      name="json_input"
                      phx-hook="InputEvent"
                      data-event="json_changed"
                      rows="12"
                      aria-invalid={@json_error && "true"}
                      aria-describedby={@json_error && "json-input-errors"}
                      class={["gf-textarea font-mono text-meta", @json_error && "gf-textarea-error"]}
                      phx-debounce="500"
                    >{@json_input}</textarea>
                    <p
                      :if={@json_error}
                      id="json-input-errors"
                      class="mt-1 text-meta text-danger"
                    >
                      {@json_error}
                    </p>
                  </div>
                </div>
              </.section>

              <.section title="About the key">
                <div class="flex flex-col gap-block">
                  <div class="grid grid-cols-1 gap-block md:grid-cols-2">
                    <.input field={@form[:title]} schema={Key} type="text" label="Title" />
                    <.input field={@form[:subtitle]} type="text" label="Subtitle" />
                    <.input
                      field={@form[:slug]}
                      type="text"
                      label="Slug"
                      placeholder="made from the title if blank"
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
                  <div class="grid grid-cols-1 gap-block md:grid-cols-2">
                    <.input field={@form[:citation]} type="text" label="Citation" />
                    <.input field={@form[:citation_url]} type="text" label="Citation URL" />
                  </div>
                </div>
              </.section>

              <div class="flex justify-end border-t border-line pt-block">
                <.form_actions form_dirty={@form_dirty} mode={@mode} create_label="Create key" />
              </div>
            </.form>

            <.section :if={@mode == :edit} id="key-images" title="Key images">
              <.live_component
                module={GallformersWeb.Admin.ContentImageManager}
                id="key-content-images"
                owner_type={:key}
                owner_id={@key.id}
                current_user={@current_user}
              />
            </.section>
          </div>

          <.rail :if={@mode == :edit} width={:narrow}>
            <.panel id="pdfs" title="PDFs">
              <p class="mb-3 text-ui text-ink-2">
                The printable versions of the key. They are rebuilt when it is saved; rebuild them by hand if they look out of date.
              </p>
              <.button variant="secondary" phx-click="regenerate_pdfs">Regenerate PDFs</.button>
            </.panel>
            <.panel id="danger" variant={:danger} title="Delete">
              <p class="mb-3 text-ui text-ink-2">
                Deletes the key, its couplets and every image it owns. You'll be asked to type its title.
              </p>
              <.button variant="danger" phx-click="delete">Delete…</.button>
            </.panel>
          </.rail>
        </div>

        <.discard_confirm_modal show={@show_discard_confirm} />

        <.dangerous_delete_modal
          :if={@key}
          show={@show_delete_modal}
          item_type="identification key"
          item_name={@key.title}
          consequences={[
            "The complete identification key and all of its couplets will be permanently deleted.",
            "All images owned by this key will be deleted from storage."
          ]}
          confirmation_value={@delete_confirmation}
        />
      </div>
    </Layouts.admin>
    """
  end
end
