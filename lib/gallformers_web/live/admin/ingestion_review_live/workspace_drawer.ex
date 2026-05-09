defmodule GallformersWeb.Admin.IngestionReviewLive.WorkspaceDrawer do
  use GallformersWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="workspace-drawer">
      <div
        :if={@drawer_open}
        class="fixed inset-0 z-40 bg-black/20 transition-opacity"
        phx-click="toggle_drawer"
      />

      <aside class={[
        "fixed top-0 right-0 z-50 h-full w-full max-w-[540px] bg-white shadow-xl transition-transform duration-300",
        if(@drawer_open, do: "translate-x-0", else: "translate-x-full")
      ]}>
        <div class="flex h-full flex-col">
          <div class="flex items-center justify-between border-b border-gray-200 px-4 py-3">
            <h3 class="text-sm font-semibold text-gray-900">Extracted source text</h3>
            <button
              type="button"
              phx-click="toggle_drawer"
              class="rounded p-1 text-gray-400 hover:text-gray-600"
            >
              <.icon name="ph-x" class="size-4" />
            </button>
          </div>

          <div class="flex-1 overflow-y-auto p-4">
            <pre
              :if={@source_text}
              class="whitespace-pre-wrap font-mono text-xs text-gray-700 leading-relaxed"
            >{@source_text}</pre>
            <p :if={!@source_text} class="text-sm text-gray-400 italic">
              No source text available.
            </p>
          </div>
        </div>
      </aside>
    </div>
    """
  end
end
