defmodule GallformersWeb.Admin.PipelineConfigLive.Index do
  use GallformersWeb, :live_view

  alias Gallformers.IngestionPipeline.PipelineConfigs

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:current_user, session["current_user"])
      |> assign(:page_title, "Pipeline Configs")
      |> load_configs()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    config = PipelineConfigs.get_pipeline_config!(String.to_integer(id))

    case PipelineConfigs.delete_pipeline_config(config) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pipeline config deleted")
         |> load_configs()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete pipeline config")}
    end
  end

  defp load_configs(socket) do
    assign(socket, :configs, PipelineConfigs.list_pipeline_configs())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Pipeline Configs">
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <div />
          <.link navigate={~p"/admin/pipeline-configs/new"} class="gf-btn gf-btn-primary">
            New Config
          </.link>
        </div>

        <div class="bg-white shadow rounded-lg overflow-hidden">
          <table class="gf-table gf-table-dark">
            <thead>
              <tr>
                <th>Name</th>
                <th>LLM Model (clean)</th>
                <th>Created</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={config <- @configs} id={"config-#{config.id}"}>
                <td>
                  <.link
                    navigate={~p"/admin/pipeline-configs/#{config.id}"}
                    class="hover:underline font-medium"
                  >
                    {config.name}
                  </.link>
                </td>
                <td class="text-gray-500">
                  {get_in(config.config, ["llm_clean", "model"]) || "—"}
                </td>
                <td class="text-gray-500">
                  {format_date(config.inserted_at, :short)}
                </td>
                <td class="text-right">
                  <.table_actions>
                    <.action_button
                      icon="ph-pencil-simple"
                      label="Edit"
                      navigate={~p"/admin/pipeline-configs/#{config.id}"}
                      variant="primary"
                    />
                    <.action_button
                      icon="ph-trash"
                      label="Delete"
                      variant="danger"
                      phx-click="delete"
                      phx-value-id={config.id}
                      confirm="Are you sure? Ingestions using this config will lose their config reference."
                    />
                  </.table_actions>
                </td>
              </tr>
              <tr :if={@configs == []}>
                <td colspan="4" class="px-6 py-8 text-center text-gray-500">
                  No pipeline configs yet.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
