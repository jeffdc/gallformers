defmodule GallformersWeb.Admin.GlossaryLive.Form do
  @moduledoc """
  The glossary admin's form (design system, matter bc0d; the admin edit
  page pattern): the word, definition and source URLs; Cancel (asking first
  when there are unsaved changes) and Save; for an entry, View on site, and
  Delete in the danger panel through a confirmation dialog.
  """
  use GallformersWeb, :live_view
  use GallformersWeb.Admin.FormHelpers, crud_helpers: true

  import GallformersWeb.Admin.FormComponents, only: [form_actions: 1]

  alias Phoenix.LiveView.JS

  alias Gallformers.Glossaries.Glossary

  # Required callbacks for FormHelpers
  @impl GallformersWeb.Admin.FormHelpers
  def entity_key, do: :entry
  @impl GallformersWeb.Admin.FormHelpers
  def entity_struct, do: Gallformers.Glossaries.Glossary
  @impl GallformersWeb.Admin.FormHelpers
  def list_path, do: ~p"/admin/glossary"
  @impl GallformersWeb.Admin.FormHelpers
  def form_key, do: "glossary"
  @impl GallformersWeb.Admin.FormHelpers
  def load_entity(id), do: Gallformers.Glossaries.get_glossary!(id)
  @impl GallformersWeb.Admin.FormHelpers
  def change_entity(entity, params \\ %{}),
    do: Gallformers.Glossaries.change_glossary(entity, params)

  @impl GallformersWeb.Admin.FormHelpers
  def create_entity(params), do: Gallformers.Glossaries.create_glossary(params)
  @impl GallformersWeb.Admin.FormHelpers
  def update_entity(entity, params), do: Gallformers.Glossaries.update_glossary(entity, params)
  @impl GallformersWeb.Admin.FormHelpers
  def delete_entity(entity), do: Gallformers.Glossaries.delete_glossary(entity)

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> init_admin_form(session, page_title: "Glossary Entry")
     |> assign(confirm_delete: false)}
  end

  def close_form(socket) do
    push_navigate(socket, to: list_path())
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params), do: apply_new_action(socket)
  defp apply_action(socket, :edit, %{"id" => id}), do: apply_edit_action(socket, id)

  @impl true
  def handle_event("validate", params, socket), do: handle_validate(params, socket)

  @impl true
  def handle_event("save", params, socket), do: handle_save(params, socket)

  @impl true
  def handle_event("delete", params, socket), do: handle_delete(params, socket)

  def handle_event("confirm_delete", _params, socket),
    do: {:noreply, assign(socket, confirm_delete: true)}

  def handle_event("cancel_delete", _params, socket),
    do: {:noreply, assign(socket, confirm_delete: false)}

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(request_cancel cancel_discard confirm_discard) do
    handle_form_event(event, params, socket)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:crumb navigate={~p"/admin/glossary"}>Glossary</:crumb>
          <:title>{if @mode == :edit, do: @entry.word, else: "New glossary entry"}</:title>
          <:description>
            Entries are linked automatically wherever their word appears in descriptions and notes. Use lowercase unless the term is a proper noun.
          </:description>
          <:action :if={@mode == :edit}>
            <.button
              href={"/glossary##{String.downcase(@entry.word)}"}
              variant="ghost"
              size="sm"
              icon="ph-arrow-square-out"
            >
              View on site
            </.button>
          </:action>
        </.page_header>

        <div class="gf-with-rail">
          <.form
            for={@form}
            id="glossary-form"
            phx-change="validate"
            phx-submit="save"
            class="flex max-w-form min-w-0 flex-col gap-block"
          >
            <div>
              <.input
                field={@form[:word]}
                schema={Glossary}
                type="text"
                label="Word"
                placeholder="lowercase unless a proper noun"
              />
            </div>
            <div>
              <.input
                field={@form[:definition]}
                schema={Glossary}
                type="textarea"
                label="Definition"
                rows="4"
              />
            </div>
            <div>
              <.input
                field={@form[:urls]}
                schema={Glossary}
                type="textarea"
                label="Source URLs"
                rows="2"
              />
              <p class="gf-hint">One per line: where the definition comes from.</p>
            </div>
            <div class="flex justify-end border-t border-line pt-block">
              <.form_actions form_dirty={@form_dirty} mode={@mode} create_label="Create entry" />
            </div>
          </.form>

          <.rail :if={@mode == :edit} width={:narrow}>
            <.panel id="danger" variant={:danger} title="Delete">
              <p class="mb-3 text-ui text-ink-2">
                Removes the entry. Text that links its word stops linking it.
              </p>
              <.button variant="danger" phx-click="confirm_delete">Delete…</.button>
            </.panel>
          </.rail>
        </div>

        <.dialog
          :if={@confirm_delete}
          id="delete-entry"
          title="Delete this entry?"
          show
          on_cancel={JS.push("cancel_delete")}
        >
          <p class="text-ui text-ink">
            Delete “{@entry.word}” from the glossary? This can't be undone.
          </p>
          <:actions>
            <.button variant="ghost" phx-click="cancel_delete">Keep it</.button>
            <.button variant="danger" phx-click="delete">Delete</.button>
          </:actions>
        </.dialog>

        <.discard_confirm_modal show={@show_discard_confirm} />
      </div>
    </Layouts.admin>
    """
  end
end
