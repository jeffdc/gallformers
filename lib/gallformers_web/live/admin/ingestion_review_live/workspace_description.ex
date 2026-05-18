defmodule GallformersWeb.Admin.IngestionReviewLive.WorkspaceDescription do
  @moduledoc """
  Chunk-picker workspace section for the curator-built description.

  The curator selects paragraphs (`evidence_prose`) and the draft is the
  concatenation of their `text` in document order. The curator can also edit
  the draft inline; once the draft is dirty, toggling chunks requires a
  confirm prompt to overwrite.

  Inline by design — per project CLAUDE.md, the chunk cards, sticky preview
  pane, and disclosure control all live in this file. No reusable extraction.
  """
  use GallformersWeb, :live_component

  alias Phoenix.LiveView.JS

  @impl true
  def update(assigns, socket) do
    evidence_prose = list_of_maps(assigns[:evidence_prose])
    existing_description = existing_description(assigns[:existing_gall])

    hydrated_selection = hydrate_selection(assigns[:hydrated_selection])
    hydrated_mode = hydrate_mode(assigns[:hydrated_mode])
    hydrated_draft_dirty = hydrate_dirty(assigns[:hydrated_draft_dirty])
    hydrated_draft = assigns[:hydrated_draft]

    socket =
      socket
      |> assign(assigns)
      |> assign(:evidence_prose_sorted, sort_by_document_order(evidence_prose))
      |> assign(:existing_description, existing_description)
      |> assign_new(:selection, fn ->
        hydrated_selection || default_selection(evidence_prose)
      end)
      |> assign_new(:disclosure_level, fn -> :high end)
      |> assign_new(:mode, fn -> hydrated_mode || :replace end)
      |> assign_new(:draft_dirty, fn -> hydrated_draft_dirty || false end)
      |> assign_new(:edit_open, fn -> false end)
      |> assign_new(:context_span_id, fn -> nil end)

    # Set the initial draft from selection when not yet present.
    socket =
      assign_new(socket, :draft, fn ->
        hydrated_draft ||
          compute_draft(socket.assigns.evidence_prose_sorted, socket.assigns.selection)
      end)

    {:ok, socket}
  end

  defp hydrate_selection(nil), do: nil

  defp hydrate_selection(selection) when is_list(selection) do
    case Enum.filter(selection, &is_binary/1) do
      [] -> nil
      ids -> MapSet.new(ids)
    end
  end

  defp hydrate_selection(%MapSet{} = selection), do: selection
  defp hydrate_selection(_), do: nil

  defp hydrate_mode(mode) when mode in [:keep, :append, :replace], do: mode
  defp hydrate_mode("keep"), do: :keep
  defp hydrate_mode("append"), do: :append
  defp hydrate_mode("replace"), do: :replace
  defp hydrate_mode(_), do: nil

  defp hydrate_dirty(true), do: true
  defp hydrate_dirty(false), do: false
  defp hydrate_dirty(_), do: nil

  # --- Events ---

  @impl true
  def handle_event("toggle_chunk", %{"span-id" => span_id}, socket) do
    selection =
      if MapSet.member?(socket.assigns.selection, span_id) do
        MapSet.delete(socket.assigns.selection, span_id)
      else
        MapSet.put(socket.assigns.selection, span_id)
      end

    draft =
      if socket.assigns.draft_dirty do
        socket.assigns.draft
      else
        compute_draft(socket.assigns.evidence_prose_sorted, selection)
      end

    socket =
      socket
      |> assign(:selection, selection)
      |> assign(:draft, draft)

    notify_parent(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_disclosure", %{"level" => level}, socket) do
    {:noreply, assign(socket, :disclosure_level, normalize_level(level))}
  end

  @impl true
  def handle_event("open_edit", _params, socket) do
    {:noreply, assign(socket, :edit_open, true)}
  end

  @impl true
  def handle_event("close_edit", _params, socket) do
    {:noreply, assign(socket, :edit_open, false)}
  end

  @impl true
  def handle_event("update_draft", %{"value" => text}, socket) do
    socket =
      socket
      |> assign(:draft, text)
      |> assign(:draft_dirty, true)

    notify_parent(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("regenerate_draft", _params, socket) do
    draft = compute_draft(socket.assigns.evidence_prose_sorted, socket.assigns.selection)

    socket =
      socket
      |> assign(:draft, draft)
      |> assign(:draft_dirty, false)

    notify_parent(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("open_context", %{"span-id" => span_id}, socket) do
    {:noreply, assign(socket, :context_span_id, span_id)}
  end

  @impl true
  def handle_event("close_context", _params, socket) do
    {:noreply, assign(socket, :context_span_id, nil)}
  end

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    socket = assign(socket, :mode, normalize_mode(mode))
    notify_parent(socket)
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    paragraphs = assigns.evidence_prose_sorted
    visible = filter_by_disclosure(paragraphs, assigns.disclosure_level)

    context_chunk =
      if assigns.context_span_id,
        do: Enum.find(paragraphs, &(get_str(&1, "span_id") == assigns.context_span_id))

    char_count = String.length(assigns.draft || "")
    selected_count = MapSet.size(assigns.selection)

    show_mode_selector =
      assigns[:existing_description] not in [nil, ""]

    assigns =
      assigns
      |> assign(:visible, visible)
      |> assign(:context_chunk, context_chunk)
      |> assign(:char_count, char_count)
      |> assign(:selected_count, selected_count)
      |> assign(:show_mode_selector, show_mode_selector)

    ~H"""
    <section
      id="workspace-section-description"
      class="rounded-lg border border-gray-200 p-4 space-y-4"
    >
      <div class="space-y-1">
        <h3 class="text-base font-semibold text-gray-900">Description</h3>
        <p class="text-xs text-gray-500">
          Pick the source paragraphs that should form the gall's description. The draft below is
          their concatenation, which you can edit before committing.
        </p>
      </div>

      <%!-- 1. Sticky-to-section draft preview pane --%>
      <div class="sticky top-2 z-10 rounded-lg border border-gray-200 bg-white p-3 shadow-sm space-y-2">
        <div class="flex items-center justify-between">
          <div class="text-xs font-medium text-gray-700">
            Draft preview ({@selected_count} chunks · {@char_count} chars)
          </div>
          <button
            type="button"
            phx-target={@myself}
            phx-click={if @edit_open, do: "close_edit", else: "open_edit"}
            class="text-xs font-medium text-gf-maroon hover:underline"
          >
            <%= if @edit_open do %>
              Done editing
            <% else %>
              Edit draft ▸
            <% end %>
          </button>
        </div>

        <%= if @edit_open do %>
          <textarea
            id="workspace-description-draft-textarea"
            phx-target={@myself}
            phx-blur="update_draft"
            rows="6"
            class="w-full rounded-md border-gray-300 text-sm focus:border-gf-maroon focus:ring-gf-maroon"
          >{@draft}</textarea>
        <% else %>
          <div
            id="workspace-description-draft-preview"
            class="whitespace-pre-wrap rounded-md bg-gray-50 p-2 text-sm text-gray-800 min-h-[3rem] max-h-64 overflow-y-auto"
          >
            <%= if (@draft || "") == "" do %>
              <span class="italic text-gray-400">No chunks selected.</span>
            <% else %>
              {@draft}
            <% end %>
          </div>
        <% end %>

        <button
          :if={@draft_dirty}
          type="button"
          phx-target={@myself}
          phx-click="regenerate_draft"
          phx-confirm="You've edited the draft. Discard your edits and regenerate from chunks?"
          class="text-xs text-gray-500 hover:underline"
        >
          Regenerate from picks
        </button>
      </div>

      <%!-- 2. Pick chunks header --%>
      <div class="flex items-center justify-between">
        <h4 class="text-sm font-semibold text-gray-800">Pick chunks</h4>
      </div>

      <%!-- 3. Cumulative disclosure control --%>
      <div class="flex gap-1 rounded-lg bg-gray-100 p-1 w-fit">
        <.disclosure_button
          level="high"
          current={@disclosure_level}
          label="High"
          prefix="●"
          myself={@myself}
        />
        <.disclosure_button
          level="medium"
          current={@disclosure_level}
          label="Medium"
          prefix="○"
          myself={@myself}
        />
        <.disclosure_button
          level="all"
          current={@disclosure_level}
          label="All"
          prefix="○"
          myself={@myself}
        />
      </div>

      <%!-- 4. Chunk list in document order --%>
      <div :if={@visible == []} class="text-sm italic text-gray-500">
        No chunks at this disclosure level.
      </div>

      <div :if={@visible != []} class="space-y-3">
        <.chunk_card
          :for={chunk <- @visible}
          chunk={chunk}
          selected={MapSet.member?(@selection, get_str(chunk, "span_id"))}
          draft_dirty={@draft_dirty}
          myself={@myself}
        />
      </div>

      <%!-- 5. Mode selector --%>
      <div :if={@show_mode_selector} class="space-y-2 pt-2 border-t border-gray-200">
        <div class="text-xs font-medium uppercase tracking-wide text-gray-500">
          Apply as
        </div>
        <div class="flex gap-2">
          <.mode_button mode="keep" current={@mode} label="Keep current" myself={@myself} />
          <.mode_button mode="append" current={@mode} label="Append" myself={@myself} />
          <.mode_button mode="replace" current={@mode} label="Replace" myself={@myself} />
        </div>
        <div class="rounded-md bg-gray-50 p-3 text-xs">
          <div class="font-medium text-gray-500 mb-1">Current description</div>
          <p class="italic text-gray-600">{@existing_description}</p>
        </div>
      </div>

      <%!-- 6. View-in-context modal --%>
      <.modal
        :if={@context_chunk}
        id="workspace-description-context-modal"
        show
        class="max-w-[90vw]"
        on_cancel={JS.push("close_context", target: @myself)}
      >
        <:header>
          <div class="flex flex-wrap items-center gap-2 text-sm">
            <span class="font-medium">p. {get_int(@context_chunk, "page")}</span>
            <span class="font-mono text-xs text-gray-500">{get_str(@context_chunk, "span_id")}</span>
            <.chip
              :for={field <- get_list(@context_chunk, "cited_by_fields")}
              size="sm"
            >
              {field}
            </.chip>
          </div>
        </:header>
        <:body>
          <div class="max-h-[80vh] overflow-y-auto">
            <pre
              id="workspace-description-context-pre"
              phx-hook="ScrollHighlightIntoView"
              phx-target={@myself}
              class="whitespace-pre-wrap font-mono text-sm leading-relaxed"
            ><%= render_context_body(@normalized_text, @context_chunk) %></pre>
          </div>
        </:body>
      </.modal>
    </section>
    """
  end

  # --- Inline subcomponents (per project CLAUDE.md, no extraction) ---

  attr :chunk, :map, required: true
  attr :selected, :boolean, required: true
  attr :draft_dirty, :boolean, required: true
  attr :myself, :any, required: true

  defp chunk_card(assigns) do
    span_id = get_str(assigns.chunk, "span_id")
    page = get_int(assigns.chunk, "page")
    is_mention = get_bool(assigns.chunk, "is_mention")
    cited_by = get_list(assigns.chunk, "cited_by_fields")
    text = get_str(assigns.chunk, "text")

    confirm_value =
      if assigns.draft_dirty,
        do: "You've edited the draft. Discard your edits and regenerate from chunks?",
        else: nil

    assigns =
      assigns
      |> assign(:span_id, span_id)
      |> assign(:page, page)
      |> assign(:is_mention, is_mention)
      |> assign(:cited_by, cited_by)
      |> assign(:text, text)
      |> assign(:confirm_value, confirm_value)

    ~H"""
    <div
      class={[
        "rounded-md border p-3 space-y-2",
        if(@selected, do: "border-gf-maroon bg-amber-50/40", else: "border-gray-200 bg-white")
      ]}
      data-span-id={@span_id}
    >
      <div class="flex items-start gap-2">
        <input
          type="checkbox"
          phx-target={@myself}
          phx-click="toggle_chunk"
          phx-value-span-id={@span_id}
          phx-confirm={@confirm_value}
          checked={@selected}
          class="mt-1 rounded border-gray-300 text-gf-maroon focus:ring-gf-maroon"
        />
        <div class="flex-1 space-y-1">
          <div class="flex flex-wrap items-center gap-2 text-xs text-gray-500">
            <span :if={@page} class="font-medium">p. {@page}</span>
            <span class="font-mono">{@span_id}</span>
            <.badge :if={@is_mention} variant="info">mention</.badge>
            <.chip :for={field <- @cited_by} size="sm">{field}</.chip>
          </div>
          <p class="whitespace-pre-wrap text-sm leading-relaxed text-gray-800">{@text}</p>
          <button
            type="button"
            phx-target={@myself}
            phx-click="open_context"
            phx-value-span-id={@span_id}
            class="text-xs text-gf-maroon hover:underline"
          >
            view in context ↗
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :level, :string, required: true
  attr :current, :atom, required: true
  attr :label, :string, required: true
  attr :prefix, :string, required: true
  attr :myself, :any, required: true

  defp disclosure_button(assigns) do
    active = to_string(assigns.current) == assigns.level

    assigns = assign(assigns, :active, active)

    ~H"""
    <button
      type="button"
      phx-target={@myself}
      phx-click="set_disclosure"
      phx-value-level={@level}
      class={[
        "rounded-md px-3 py-1.5 text-xs font-medium transition",
        if(@active,
          do: "bg-white text-gray-900 shadow-sm",
          else: "text-gray-500 hover:text-gray-700"
        )
      ]}
    >
      <span class={if @active, do: "text-gf-maroon", else: "text-gray-400"}>{@prefix}</span>
      {@label}
    </button>
    """
  end

  attr :mode, :string, required: true
  attr :current, :atom, required: true
  attr :label, :string, required: true
  attr :myself, :any, required: true

  defp mode_button(assigns) do
    active = to_string(assigns.current) == assigns.mode

    assigns = assign(assigns, :active, active)

    ~H"""
    <button
      type="button"
      phx-target={@myself}
      phx-click="set_mode"
      phx-value-mode={@mode}
      class={[
        "flex-1 rounded-md px-3 py-1.5 text-xs font-medium transition",
        if(@active,
          do: "bg-white text-gray-900 shadow-sm border border-gf-maroon",
          else: "text-gray-500 hover:text-gray-700"
        )
      ]}
    >
      {@label}
    </button>
    """
  end

  # --- Helpers ---

  defp render_context_body(nil, _chunk), do: ""

  defp render_context_body(text, chunk) when is_binary(text) do
    char_start = get_int(chunk, "char_start") || 0
    char_end = get_int(chunk, "char_end") || char_start

    char_start = max(char_start, 0)
    char_end = max(char_end, char_start)

    before_str = String.slice(text, 0, char_start)
    inside = String.slice(text, char_start, char_end - char_start)
    after_str = String.slice(text, char_end..-1//1)

    assigns = %{before_str: before_str, inside: inside, after_str: after_str}

    ~H"""
    {@before_str}<mark>{@inside}</mark>{@after_str}
    """
  end

  defp default_selection(prose) do
    prose
    |> Enum.filter(fn p ->
      get_str(p, "relevance") == "high" or get_bool(p, "is_cited") == true
    end)
    |> Enum.map(&get_str(&1, "span_id"))
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp compute_draft(sorted_prose, selection) do
    sorted_prose
    |> Enum.filter(fn p -> MapSet.member?(selection, get_str(p, "span_id")) end)
    |> Enum.map(&get_str(&1, "text"))
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  defp sort_by_document_order(prose) do
    Enum.sort_by(prose, fn p ->
      {get_int(p, "page") || 0, get_int(p, "char_start") || 0}
    end)
  end

  defp filter_by_disclosure(prose, level) do
    Enum.filter(prose, &keep_at_level?(&1, level))
  end

  defp keep_at_level?(paragraph, :high) do
    get_str(paragraph, "relevance") == "high" or get_bool(paragraph, "is_cited") == true
  end

  defp keep_at_level?(paragraph, :medium) do
    keep_at_level?(paragraph, :high) or get_str(paragraph, "relevance") == "medium"
  end

  defp keep_at_level?(_paragraph, :all), do: true

  defp normalize_level("high"), do: :high
  defp normalize_level("medium"), do: :medium
  defp normalize_level("all"), do: :all
  defp normalize_level(_), do: :high

  defp normalize_mode("keep"), do: :keep
  defp normalize_mode("append"), do: :append
  defp normalize_mode("replace"), do: :replace
  defp normalize_mode(_), do: :replace

  defp notify_parent(socket) do
    send(
      self(),
      {:description_updated,
       %{
         selection: MapSet.to_list(socket.assigns.selection),
         draft: socket.assigns.draft,
         mode: socket.assigns.mode,
         dirty: socket.assigns.draft_dirty
       }}
    )
  end

  defp existing_description(nil), do: nil

  defp existing_description(%{description: description}) when description in [nil, ""], do: nil

  defp existing_description(%{description: description}), do: description

  defp existing_description(_), do: nil

  defp list_of_maps(value) when is_list(value), do: value
  defp list_of_maps(_), do: []

  defp get_str(map, key) do
    case Map.get(map, key) do
      v when is_binary(v) -> v
      _ -> nil
    end
  end

  defp get_int(map, key) do
    case Map.get(map, key) do
      v when is_integer(v) -> v
      _ -> nil
    end
  end

  defp get_bool(map, key) do
    case Map.get(map, key) do
      true -> true
      false -> false
      _ -> false
    end
  end

  defp get_list(map, key) do
    case Map.get(map, key) do
      v when is_list(v) -> v
      _ -> []
    end
  end
end
