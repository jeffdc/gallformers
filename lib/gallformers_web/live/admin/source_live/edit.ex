defmodule GallformersWeb.Admin.SourceLive.Edit do
  @moduledoc """
  The Source editor (matter a856, Task 10): a Source's details — today's
  columns, shown on the public pages, and the new back-end's description —
  with today's validation (`Gallformers.Sources.Source.changeset/2`); its
  retraction by a retraction notice (another Source, picked by search) on a
  date; and undoing a retraction. There is no delete: Facts and legacy
  citations refer to Sources.

  Every write goes through `Gallformers.Import.record_source_edit/2` as the
  signed-in admin (the `:admin` live session's actor), which recomputes the
  standings of the Facts the Source supports and records the edit in the
  replay log.
  """
  use GallformersWeb, :live_view
  use GallformersWeb.Admin.FormHelpers

  import GallformersWeb.Admin.FormComponents, only: [form_actions: 1]

  alias Gallformers.Import
  alias Gallformers.Licenses
  alias Gallformers.Sources
  alias Gallformers.Sources.Source
  alias Phoenix.HTML.Form

  @notice_results 10

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {source_id, ""} -> mount_source(socket, Sources.get_source(source_id))
      _ -> mount_source(socket, nil)
    end
  end

  defp mount_source(socket, nil) do
    {:ok,
     socket
     |> put_flash(:error, "Source not found")
     |> push_navigate(to: ~p"/admin/sources")}
  end

  defp mount_source(socket, %Source{} = source) do
    {:ok,
     socket
     |> init_form_state()
     |> assign_source(source)
     |> clear_notice()}
  end

  def close_form(socket), do: push_navigate(socket, to: ~p"/admin/sources")

  # -- details -----------------------------------------------------------------

  @impl true
  def handle_event("validate", %{"source" => params}, socket) do
    changeset =
      socket.assigns.source
      |> Sources.change_source(source_params(params))
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form, to_form(changeset)) |> mark_dirty()}
  end

  def handle_event("save", %{"source" => params}, socket) do
    edit = {:update_details, socket.assigns.source, source_params(params)}

    case Import.record_source_edit(socket.assigns.actor, edit) do
      {:ok, source} ->
        {:noreply,
         socket
         |> put_flash(:info, "Source saved")
         |> reset_dirty()
         |> assign_source(source)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # -- retraction --------------------------------------------------------------

  def handle_event("search_notice", %{"value" => query}, socket) do
    results =
      if String.length(String.trim(query)) >= 2 do
        query
        |> Sources.search_sources()
        |> Enum.reject(&(&1.id == socket.assigns.source.id))
        |> Enum.take(@notice_results)
      else
        []
      end

    {:noreply, assign(socket, notice_query: query, notice_results: results)}
  end

  def handle_event("select_notice", %{"id" => id}, socket) do
    case Sources.get_source(String.to_integer(id)) do
      %Source{} = notice ->
        date = socket.assigns.retract_form[:retracted_on].value

        {:noreply,
         socket
         |> assign(notice: notice, notice_query: "", notice_results: [], notice_error: nil)
         |> assign(:retract_form, retract_form(date_or_authored(date, notice)))}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("clear_notice", _params, socket) do
    {:noreply, assign(socket, notice: nil, notice_query: "", notice_results: [])}
  end

  def handle_event("retract", %{"retract" => %{"retracted_on" => on}}, socket) do
    %{notice: notice, source: source, actor: actor} = socket.assigns

    with {:notice, %Source{}} <- {:notice, notice},
         {:date, {:ok, date}} <- {:date, Date.from_iso8601(on)},
         {:ok, source} <- Import.record_source_edit(actor, {:retract, source, notice, date}) do
      {:noreply,
       socket
       |> put_flash(:info, "Source retracted")
       |> assign_source(source)
       |> clear_notice()}
    else
      {:notice, nil} ->
        {:noreply, assign(socket, :notice_error, "Pick the retraction notice")}

      {:date, _error} ->
        {:noreply,
         assign(socket, :retract_form, retract_form(on, retracted_on: {"must be a date", []}))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Could not retract: #{error_text(changeset)}")}
    end
  end

  def handle_event("unretract", _params, socket) do
    case Import.record_source_edit(socket.assigns.actor, {:unretract, socket.assigns.source}) do
      {:ok, source} ->
        {:noreply,
         socket
         |> put_flash(:info, "Retraction undone")
         |> assign_source(source)}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Could not undo: #{error_text(changeset)}")}
    end
  end

  def handle_event(event, params, socket)
      when event in ~w(request_cancel cancel_discard confirm_discard) do
    handle_form_event(event, params, socket)
  end

  # -- helpers -----------------------------------------------------------------

  defp assign_source(socket, %Source{} = source) do
    # The form shows the authored date as the partial date it was given.
    source = %{source | authored: Source.authored(source)}

    socket
    |> assign(:source, source)
    |> assign(:page_title, source.title)
    |> assign(:form, to_form(Sources.change_source(source)))
    |> assign(:retracted_by, source.retracted_by_id && Sources.get_source(source.retracted_by_id))
  end

  defp clear_notice(socket) do
    assign(socket,
      notice: nil,
      notice_query: "",
      notice_results: [],
      notice_error: nil,
      retract_form: retract_form("")
    )
  end

  defp retract_form(date, errors \\ []),
    do: to_form(%{"retracted_on" => date}, as: :retract, errors: errors)

  # A notice's own date is the usual date of the retraction.
  defp date_or_authored(date, %Source{authored_date: %Date{} = authored})
       when date in [nil, ""],
       do: Date.to_iso8601(authored)

  defp date_or_authored(date, _notice), do: date

  # Authors are entered one per line.
  defp source_params(%{"authors" => authors} = params) when is_binary(authors) do
    names =
      authors
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Map.put(params, "authors", names)
  end

  defp source_params(params), do: params

  defp error_text(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp error_text(reason), do: inspect(reason)

  defp authors_text(form) do
    case Form.input_value(form, :authors) do
      authors when is_list(authors) -> Enum.join(authors, "\n")
      other -> other
    end
  end

  # Today's license values, plus the Source's own if it is another.
  defp license_options(form) do
    current = Form.input_value(form, :license)
    extra = if current in [nil, ""] or current in Licenses.all(), do: [], else: [current]
    Licenses.all() ++ extra
  end

  defp kind_options, do: Enum.map(Ecto.Enum.values(Source, :kind), &{kind_label(&1), &1})

  defp kind_label(kind),
    do: kind |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <:page_title_html>
        Editing <em class="font-bold">{@source.title}</em>
      </:page_title_html>
      <Layouts.admin_edit_layout
        back_path={~p"/admin/sources"}
        back_label="Back to Sources"
        public_url={~p"/source/#{@source.id}"}
      >
        <:intro>
          Sources arrive with imports. Correct a Source's details here, or record that it was
          retracted. Saving recomputes the standing of every Fact the Source supports.
        </:intro>

        <.form for={@form} id="source-form" phx-change="validate" phx-submit="save">
          <h2 class="text-lg font-semibold text-gray-800 mb-2">Citation</h2>
          <p class="text-sm text-gray-500 mb-3">As shown on the Source's public page.</p>

          <div class="mb-3">
            <.input field={@form[:title]} schema={Source} label="Title" />
          </div>

          <div class="grid grid-cols-2 gap-4 mb-3">
            <.input
              field={@form[:author]}
              schema={Source}
              label="Author(s)"
              placeholder="e.g., Smith, J. and Jones, M."
            />
            <.input
              field={@form[:pubyear]}
              schema={Source}
              label="Publication Year"
              placeholder="e.g., 2023"
            />
          </div>

          <div class="mb-3">
            <.input
              field={@form[:link]}
              type="url"
              label="Reference Link"
              placeholder="https://..."
            />
          </div>

          <% current_license = Form.input_value(@form, :license) %>
          <div class="grid grid-cols-2 gap-4 mb-3">
            <.input
              field={@form[:license]}
              schema={Source}
              type="select"
              label="License"
              prompt="Select license"
              options={license_options(@form)}
            />
            <div>
              <%= if Licenses.url_readonly?(current_license) do %>
                <.input
                  field={@form[:licenselink]}
                  type="url"
                  label="License Link"
                  value={Licenses.url(current_license)}
                  readonly
                  class="bg-gray-100 text-gray-500 cursor-not-allowed"
                />
                <p class="mt-1 text-xs text-gray-500">Auto-filled from license selection</p>
              <% else %>
                <.input field={@form[:licenselink]} type="url" label="License Link" />
              <% end %>
            </div>
          </div>

          <div class="mb-3">
            <.input
              field={@form[:citation]}
              schema={Source}
              type="textarea"
              label="Citation (MLA format)"
              rows="4"
            />
          </div>

          <div class="mb-6">
            <.input
              type="checkbox"
              field={@form[:datacomplete]}
              label="All information from this source has been entered into the database"
            />
          </div>

          <h2 class="text-lg font-semibold text-gray-800 mb-2">Description</h2>
          <p class="text-sm text-gray-500 mb-3">
            The Source as imports describe it.
          </p>

          <div class="grid grid-cols-2 gap-4 mb-3">
            <.input
              field={@form[:kind]}
              type="select"
              label="Kind"
              prompt="Select kind"
              options={kind_options()}
            />
            <.input
              field={@form[:authored]}
              label="Authored"
              placeholder="YYYY, YYYY-MM or YYYY-MM-DD"
            />
          </div>

          <div class="grid grid-cols-2 gap-4 mb-3">
            <.input
              field={@form[:authors]}
              type="textarea"
              label="Authors (one per line)"
              value={authors_text(@form)}
              rows="3"
            />
            <.input
              field={@form[:authored_as_written]}
              label="Date as written"
              placeholder="e.g., Spring 1897"
            />
          </div>

          <div class="grid grid-cols-3 gap-4 mb-3">
            <.input field={@form[:doi]} label="DOI" placeholder="10.xxxx/..." />
            <.input field={@form[:url]} type="url" label="URL" placeholder="https://..." />
            <.input field={@form[:isbn]} label="ISBN" />
          </div>

          <div class="mb-3">
            <.input field={@form[:license_as_written]} label="License as written" />
          </div>

          <div class="flex justify-end pt-4 border-t border-gray-200">
            <.form_actions form_dirty={@form_dirty} mode={:edit} />
          </div>
        </.form>

        <section id="retraction" class="mt-8 pt-6 border-t border-gray-200">
          <h2 class="text-lg font-semibold text-gray-800 mb-3">Retraction</h2>

          <%= if @source.retracted_by_id do %>
            <.alert variant="warning">
              Retracted by
              <.link
                :if={@retracted_by}
                navigate={~p"/admin/sources/#{@source.retracted_by_id}"}
                class="font-medium hover:underline"
              >
                {@retracted_by.title}
              </.link>
              on {@source.retracted_on}. Its stances are cancelled.
            </.alert>
            <button
              id="unretract-button"
              type="button"
              phx-click="unretract"
              data-confirm="Undo this retraction? The Source's stances count again."
              class="gf-btn gf-btn-soft mt-3"
            >
              Undo retraction
            </button>
          <% else %>
            <p class="text-sm text-gray-600 mb-3">
              A retraction cancels all of this Source's stances. Pick the retraction notice (another
              Source) and the date of the retraction.
            </p>
            <div class="max-w-xl space-y-3">
              <.typeahead
                id="notice-picker"
                label="Retraction notice"
                placeholder="Search for the notice..."
                query={@notice_query}
                results={@notice_results}
                selected={@notice}
                search_event="search_notice"
                select_event="select_notice"
                clear_event="clear_notice"
                display_fn={& &1.title}
              >
                <:result :let={notice}>
                  <div class="flex flex-col">
                    <span class="text-gray-900">{notice.title}</span>
                    <span class="text-xs text-gray-500">{notice.author} ({notice.pubyear})</span>
                  </div>
                </:result>
              </.typeahead>
              <p :if={@notice_error} class="text-sm text-red-600">{@notice_error}</p>

              <.form for={@retract_form} id="retract-form" phx-submit="retract">
                <.input field={@retract_form[:retracted_on]} type="date" label="Retracted on" />
                <button type="submit" class="gf-btn gf-btn-danger mt-3">Retract</button>
              </.form>
            </div>
          <% end %>
        </section>

        <.record_metadata inserted_at={@source.inserted_at} updated_at={@source.updated_at} />

        <.discard_confirm_modal show={@show_discard_confirm} />
      </Layouts.admin_edit_layout>
    </Layouts.admin>
    """
  end
end
