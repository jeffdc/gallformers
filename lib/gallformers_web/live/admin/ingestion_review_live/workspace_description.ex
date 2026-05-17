defmodule GallformersWeb.Admin.IngestionReviewLive.WorkspaceDescription do
  use GallformersWeb, :live_component

  @impl true
  def update(assigns, socket) do
    existing_description =
      if assigns[:existing_gall], do: assigns.existing_gall.description, else: nil

    extracted_prose = assigns.workspace.description_prose || ""

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:mode, fn ->
        if existing_description, do: "keep", else: "replace"
      end)
      |> assign(:existing_description, existing_description)
      |> assign(:extracted_prose, extracted_prose)

    {:ok, socket}
  end

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    text = compute_text(mode, socket.assigns.existing_description, socket.assigns.extracted_prose)
    send(self(), {:description_updated, mode, text})
    {:noreply, assign(socket, :mode, mode)}
  end

  @impl true
  def handle_event("update_description", %{"value" => text}, socket) do
    send(self(), {:description_updated, socket.assigns.mode, text})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    decision = assigns.workspace.species_review.decision
    show_segmented = decision == "mapped" && assigns.existing_description != nil

    assigns = assign(assigns, :show_segmented, show_segmented)

    ~H"""
    <section
      id="workspace-section-description"
      class="rounded-lg border border-gray-200 p-4 space-y-4"
    >
      <div class="space-y-1">
        <h3 class="text-base font-semibold text-gray-900">Description summary</h3>
        <p class="text-xs text-gray-500">
          LLM-generated one-liner that goes into the gall's description field on commit.
          See <strong>Source text</strong> above for the full prose.
        </p>
      </div>

      <div class="space-y-4">
        <div :if={@show_segmented} class="flex gap-1 rounded-lg bg-gray-100 p-1">
          <.mode_button mode="keep" current={@mode} label="Keep current" myself={@myself} />
          <.mode_button mode="append" current={@mode} label="Append" myself={@myself} />
          <.mode_button mode="replace" current={@mode} label="Replace" myself={@myself} />
        </div>

        <div :if={@show_segmented && @existing_description} class="rounded-lg bg-gray-50 p-3">
          <div class="text-xs font-medium uppercase tracking-wide text-gray-500 mb-1">
            Current description
          </div>
          <p class="text-sm italic text-gray-600">{@existing_description}</p>
        </div>

        <textarea
          id="description-textarea"
          phx-target={@myself}
          phx-blur="update_description"
          rows="6"
          class="w-full rounded-lg border-gray-300 text-sm focus:border-gf-maroon focus:ring-gf-maroon"
        >{@workspace.description_prose || ""}</textarea>

        <div :if={@workspace.description_evidence != []} class="space-y-2">
          <div class="text-xs font-medium uppercase tracking-wide text-gray-500">
            Evidence from source
          </div>
          <div
            :for={evidence <- @workspace.description_evidence}
            class="rounded bg-amber-50 border border-amber-200 p-2 text-xs text-gray-700"
          >
            {evidence}
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :mode, :string, required: true
  attr :current, :string, required: true
  attr :label, :string, required: true
  attr :myself, :any, required: true

  defp mode_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="set_mode"
      phx-value-mode={@mode}
      phx-target={@myself}
      class={[
        "flex-1 rounded-md px-3 py-1.5 text-xs font-medium transition",
        if(@mode == @current,
          do: "bg-white text-gray-900 shadow-sm",
          else: "text-gray-500 hover:text-gray-700"
        )
      ]}
    >
      {@label}
    </button>
    """
  end

  defp compute_text("keep", existing, _extracted), do: existing || ""

  defp compute_text("append", existing, extracted) do
    case existing do
      nil -> extracted
      "" -> extracted
      text -> text <> "\n\n" <> extracted
    end
  end

  defp compute_text("replace", _existing, extracted), do: extracted
  defp compute_text(_, _existing, extracted), do: extracted
end
