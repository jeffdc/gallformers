defmodule GallformersWeb.Admin.FormHelpers do
  @moduledoc """
  Reusable helpers for admin form dirty state tracking, discard confirmation,
  and common CRUD patterns.

  ## Basic Usage

  In your LiveView:

      use GallformersWeb.Admin.FormHelpers

  This injects:
  - `init_form_state/1` - Call in mount to initialize assigns
  - `mark_dirty/1` - Call in validate handler to mark form as dirty
  - `handle_form_event/3` - Delegate form events to this handler
  - `close_form/1` - Override to define what happens when form is closed

  ## Example (Basic)

      def mount(_params, session, socket) do
        socket =
          socket
          |> assign(:current_user, session["current_user"])
          |> init_form_state()

        {:ok, socket}
      end

      def handle_event("validate", params, socket) do
        # ... validation logic ...
        {:noreply, mark_dirty(socket)}
      end

      def handle_event(event, params, socket) when event in ~w(request_cancel cancel_discard confirm_discard) do
        handle_form_event(event, params, socket)
      end

      # Override to define navigation on close
      def close_form(socket) do
        push_navigate(socket, to: ~p"/admin/mylist")
      end

  ## Advanced Usage with Standard CRUD Helpers

  For forms that follow standard patterns, implement the behaviour callbacks
  and use the consolidated helper functions:

      use GallformersWeb.Admin.FormHelpers, crud_helpers: true

      alias Gallformers.Sources
      alias Gallformers.Sources.Source

      # Required callbacks - all explicit, no magic
      def entity_key, do: :source
      def entity_struct, do: Source
      def list_path, do: ~p"/admin/sources"
      def load_entity(id), do: Sources.get_source!(id)
      def change_entity(entity, params \\\\ %{}), do: Sources.change_source(entity, params)
      def create_entity(params), do: Sources.create_source(params)
      def update_entity(entity, params), do: Sources.update_source(entity, params)

      # Use consolidated helpers
      def mount(_params, session, socket) do
        {:ok, init_admin_form(socket, session)}
      end

      defp apply_action(socket, :new, _params), do: apply_new_action(socket)
      defp apply_action(socket, :edit, %{"id" => id}), do: apply_edit_action(socket, id)

      def handle_event("validate", params, socket), do: handle_validate(params, socket)
      def handle_event("save", params, socket), do: handle_save(params, socket)

  ## Callbacks

  ### Required (when using crud_helpers: true)
  - `entity_key/0` - Returns the assign key atom (e.g., `:source`)
  - `entity_struct/0` - Returns the struct module (e.g., `Source`)
  - `list_path/0` - Returns the path to navigate to after save/cancel
  - `load_entity/1` - Loads entity by id (e.g., `Sources.get_source!(id)`)
  - `change_entity/2` - Returns changeset (e.g., `Sources.change_source(entity, params)`)
  - `create_entity/1` - Creates entity (e.g., `Sources.create_source(params)`)
  - `update_entity/2` - Updates entity (e.g., `Sources.update_source(entity, params)`)

  ### Optional (have defaults)
  - `form_key/0` - Form params key, defaults to `to_string(entity_key())`
  - `entity_label/0` - Human label, defaults to humanizing entity_key
  - `new_entity/0` - Returns empty struct, defaults to `struct(entity_struct())`
  - `prepare_params/1` - Transform params before save, defaults to pass-through
  - `after_create/2` - Called after successful create, defaults to flash + navigate
  - `after_update/2` - Called after successful update, defaults to flash + navigate
  """

  @doc """
  Behaviour for admin form LiveViews using the advanced helpers.
  All callbacks are optional - implement only what you need.
  """
  @callback entity_key() :: atom()
  @callback list_path() :: String.t()
  @callback form_key() :: String.t()
  @callback entity_label() :: String.t()
  @callback entity_struct() :: module()
  @callback new_entity() :: struct()
  @callback load_entity(id :: integer()) :: struct() | nil
  @callback change_entity(entity :: struct(), params :: map()) :: Ecto.Changeset.t()
  @callback create_entity(params :: map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback update_entity(entity :: struct(), params :: map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t() | term()}
  @callback delete_entity(entity :: struct()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback prepare_params(params :: map()) :: map()
  @callback after_create(socket :: Phoenix.LiveView.Socket.t(), entity :: struct()) ::
              Phoenix.LiveView.Socket.t()
  @callback after_update(socket :: Phoenix.LiveView.Socket.t(), entity :: struct()) ::
              Phoenix.LiveView.Socket.t()
  @callback after_delete(socket :: Phoenix.LiveView.Socket.t(), entity :: struct()) ::
              Phoenix.LiveView.Socket.t()

  @optional_callbacks entity_key: 0,
                      list_path: 0,
                      form_key: 0,
                      entity_label: 0,
                      entity_struct: 0,
                      new_entity: 0,
                      load_entity: 1,
                      change_entity: 2,
                      create_entity: 1,
                      update_entity: 2,
                      delete_entity: 1,
                      prepare_params: 1,
                      after_create: 2,
                      after_update: 2,
                      after_delete: 2

  defmacro __using__(opts) do
    crud_helpers = Keyword.get(opts, :crud_helpers, false)
    include_delete = Keyword.get(opts, :include_delete, true)

    # credo:disable-for-next-line Credo.Check.Refactor.LongQuoteBlocks
    quote location: :keep do
      @behaviour GallformersWeb.Admin.FormHelpers

      import GallformersWeb.Admin.FormHelpers, only: [discard_confirm_modal: 1]

      # =================================================================
      # Core dirty state tracking (always available)
      # =================================================================

      @doc """
      Initialize form state assigns. Call in mount/3.
      """
      def init_form_state(socket) do
        socket
        |> Phoenix.Component.assign(:form_dirty, false)
        |> Phoenix.Component.assign(:show_discard_confirm, false)
      end

      @doc """
      Mark the form as dirty. Call in validate handler.
      """
      def mark_dirty(socket) do
        Phoenix.Component.assign(socket, :form_dirty, true)
      end

      @doc """
      Reset the form dirty state. Call when opening a new/edit form.
      """
      def reset_dirty(socket) do
        socket
        |> Phoenix.Component.assign(:form_dirty, false)
        |> Phoenix.Component.assign(:show_discard_confirm, false)
      end

      @doc """
      Handle form-related events. Delegate from handle_event/3.
      """
      def handle_form_event("request_cancel", _params, socket) do
        if socket.assigns.form_dirty do
          {:noreply, Phoenix.Component.assign(socket, :show_discard_confirm, true)}
        else
          {:noreply, close_form(socket)}
        end
      end

      def handle_form_event("cancel_discard", _params, socket) do
        {:noreply, Phoenix.Component.assign(socket, :show_discard_confirm, false)}
      end

      def handle_form_event("confirm_discard", _params, socket) do
        socket =
          socket
          |> Phoenix.Component.assign(:form_dirty, false)
          |> Phoenix.Component.assign(:show_discard_confirm, false)
          |> close_form()

        {:noreply, socket}
      end

      @doc """
      Define what happens when the form is closed/cancelled.
      Override this in your LiveView to customize behavior.
      """
      def close_form(socket) do
        # Default implementation - override in your LiveView
        socket
      end

      defoverridable close_form: 1

      # =================================================================
      # Utility functions (always available)
      # =================================================================

      @doc """
      Validates that a name follows binomial nomenclature (Genus species or Genus x species).
      """
      def valid_species_name?(name) do
        Regex.match?(~r/^[A-Z][a-z-]+ (x )?[a-z-]+/, name)
      end

      # Conditionally include CRUD helpers if crud_helpers: true is passed
      if unquote(crud_helpers) do
        # =================================================================
        # Optional callback defaults (require context_module, entity_key, list_path)
        # =================================================================

        @doc """
        Default form params key. Override to customize.
        """
        def form_key do
          to_string(entity_key())
        end

        @doc """
        Default human-readable label. Override to customize.
        """
        def entity_label do
          entity_key()
          |> to_string()
          |> String.replace("_", " ")
          |> String.split()
          |> Enum.map_join(" ", &String.capitalize/1)
        end

        @doc """
        Default new entity creation. Override to customize.
        """
        def new_entity do
          struct(entity_struct())
        end

        @doc """
        Default params preparation. Override to transform params before save.
        """
        def prepare_params(params), do: params

        @doc """
        Default after-create behavior. Navigate to edit page for the newly created entity.
        Override to customize.
        """
        def after_create(socket, entity) do
          socket
          |> Phoenix.LiveView.put_flash(:info, "#{entity_label()} created successfully")
          |> Phoenix.LiveView.push_navigate(to: "#{list_path()}/#{entity.id}")
        end

        @doc """
        Default after-update behavior. Stays on page with fresh data.
        Override to customize.
        """
        def after_update(socket, entity) do
          # Reload the entity to get fresh data and reset the form
          changeset = change_entity(entity)

          socket
          |> Phoenix.LiveView.put_flash(:info, "#{entity_label()} updated successfully")
          |> Phoenix.Component.assign(entity_key(), entity)
          |> Phoenix.Component.assign(:form, Phoenix.Component.to_form(changeset, as: form_key()))
          |> Phoenix.Component.assign(:form_dirty, false)
        end

        if unquote(include_delete) do
          @doc """
          Default after-delete behavior. Override to customize.
          """
          def after_delete(socket, _entity) do
            socket
            |> Phoenix.LiveView.put_flash(:info, "#{entity_label()} deleted successfully")
            |> Phoenix.LiveView.push_navigate(to: list_path())
          end

          defoverridable after_delete: 2
        end

        defoverridable form_key: 0,
                       entity_label: 0,
                       new_entity: 0,
                       prepare_params: 1,
                       after_create: 2,
                       after_update: 2

        # =================================================================
        # Consolidated helper functions
        # =================================================================

        @doc """
        Standard mount setup for admin forms.
        Assigns current_user, page_title, and initializes form state.
        """
        def init_admin_form(socket, session, opts \\ []) do
          page_title = Keyword.get(opts, :page_title, entity_label())

          socket
          |> Phoenix.Component.assign(:current_user, session["current_user"])
          |> Phoenix.Component.assign(:page_title, page_title)
          |> init_form_state()
        end

        @doc """
        Apply :new action - creates empty entity and form.
        Accepts optional extra assigns as keyword list.
        """
        def apply_new_action(socket, extra_assigns \\ []) do
          entity = new_entity()
          changeset = change_entity(entity)

          socket
          |> Phoenix.Component.assign(:page_title, "New #{entity_label()}")
          |> Phoenix.Component.assign(entity_key(), entity)
          |> Phoenix.Component.assign(:form, Phoenix.Component.to_form(changeset, as: form_key()))
          |> Phoenix.Component.assign(:mode, :new)
          |> Phoenix.Component.assign(extra_assigns)
        end

        @doc """
        Apply :edit action - loads entity and creates form.
        Handles nil entity with flash and redirect.
        Accepts optional extra assigns as keyword list.
        """
        def apply_edit_action(socket, id, extra_assigns \\ []) do
          case safe_load_entity(id) do
            nil ->
              socket
              |> Phoenix.LiveView.put_flash(:error, "#{entity_label()} not found")
              |> Phoenix.LiveView.push_navigate(to: list_path())

            entity ->
              changeset = change_entity(entity)

              socket
              |> Phoenix.Component.assign(:page_title, "Edit #{entity_label()}")
              |> Phoenix.Component.assign(entity_key(), entity)
              |> Phoenix.Component.assign(
                :form,
                Phoenix.Component.to_form(changeset, as: form_key())
              )
              |> Phoenix.Component.assign(:mode, :edit)
              |> Phoenix.Component.assign(extra_assigns)
          end
        end

        @doc """
        Standard validate handler.
        Extracts params using form_key, creates changeset, marks dirty.
        """
        def handle_validate(params, socket) do
          entity_params = Map.get(params, form_key(), %{})
          entity = Map.get(socket.assigns, entity_key())

          changeset =
            entity
            |> change_entity(entity_params)
            |> Map.put(:action, :validate)

          socket =
            socket
            |> Phoenix.Component.assign(
              :form,
              Phoenix.Component.to_form(changeset, as: form_key())
            )
            |> mark_dirty()

          {:noreply, socket}
        end

        @doc """
        Standard save handler.
        Dispatches to create or update based on mode.
        """
        def handle_save(params, socket) do
          entity_params = Map.get(params, form_key(), %{})
          prepared_params = prepare_params(entity_params)

          case socket.assigns.mode do
            :new -> do_create(socket, prepared_params)
            :edit -> do_update(socket, prepared_params)
          end
        end

        if unquote(include_delete) do
          @doc """
          Standard delete handler.
          Requires delete_entity/1 callback to be implemented.
          """
          def handle_delete(_params, socket) do
            entity = Map.get(socket.assigns, entity_key())
            do_handle_delete(entity, socket)
          end

          # credo:disable-for-lines:10 Credo.Check.Refactor.Nesting
          defp do_handle_delete(entity, socket) do
            case delete_entity(entity) do
              {:ok, entity} ->
                {:noreply, after_delete(socket, entity)}

              {:error, _changeset} ->
                {:noreply,
                 Phoenix.LiveView.put_flash(socket, :error, "Failed to delete #{entity_label()}")}
            end
          end
        end

        # Private helpers

        defp safe_load_entity(id) do
          load_entity(id)
        rescue
          Ecto.NoResultsError -> nil
        end

        defp do_create(socket, params) do
          case create_entity(params) do
            {:ok, entity} ->
              {:noreply, after_create(socket, entity)}

            {:error, %Ecto.Changeset{} = changeset} ->
              {:noreply,
               Phoenix.Component.assign(socket, :form, Phoenix.Component.to_form(changeset))}
          end
        end

        defp do_update(socket, params) do
          entity = Map.get(socket.assigns, entity_key())

          case update_entity(entity, params) do
            {:ok, entity} ->
              {:noreply, after_update(socket, entity)}

            {:error, %Ecto.Changeset{} = changeset} ->
              {:noreply,
               Phoenix.Component.assign(socket, :form, Phoenix.Component.to_form(changeset))}
          end
        end

        defoverridable do_update: 2
      end
    end
  end

  use Phoenix.Component
  import GallformersWeb.CoreComponents, only: [modal: 1]

  @doc """
  Renders the discard confirmation modal.

  ## Example

      <.discard_confirm_modal show={@show_discard_confirm} />

  """
  attr :show, :boolean, required: true, doc: "whether to show the modal"

  def discard_confirm_modal(assigns) do
    ~H"""
    <.modal
      :if={@show}
      id="discard-confirm-modal"
      show
      on_cancel={Phoenix.LiveView.JS.push("cancel_discard")}
      class="gf-modal-md"
    >
      <:header>Discard Changes?</:header>
      <:body>
        <p class="text-gray-600 mb-4">
          You have unsaved changes. Are you sure you want to discard them?
        </p>
      </:body>
      <:footer>
        <button
          type="button"
          phx-click="cancel_discard"
          class="px-4 py-2 text-gray-700 border border-gray-300 rounded-md hover:bg-gray-50"
        >
          Keep Editing
        </button>
        <button
          type="button"
          phx-click="confirm_discard"
          class="px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700"
        >
          Discard Changes
        </button>
      </:footer>
    </.modal>
    """
  end
end
