defmodule GallformersWeb.Admin.PipelineConfigLive.Form do
  use GallformersWeb, :live_view
  use GallformersWeb.Admin.FormHelpers, crud_helpers: true

  import GallformersWeb.Admin.FormComponents, only: [form_actions: 1]

  alias Gallformers.IngestionPipeline.PipelineConfig
  alias Gallformers.IngestionPipeline.PipelineConfigs

  @impl GallformersWeb.Admin.FormHelpers
  def entity_key, do: :pipeline_config
  @impl GallformersWeb.Admin.FormHelpers
  def entity_struct, do: PipelineConfig
  @impl GallformersWeb.Admin.FormHelpers
  def list_path, do: ~p"/admin/pipeline-configs"
  @impl GallformersWeb.Admin.FormHelpers
  def form_key, do: "pipeline_config"
  @impl GallformersWeb.Admin.FormHelpers
  def load_entity(id), do: PipelineConfigs.get_pipeline_config!(id)
  @impl GallformersWeb.Admin.FormHelpers
  def change_entity(entity, params \\ %{}),
    do: PipelineConfigs.change_pipeline_config(entity, params)

  @impl GallformersWeb.Admin.FormHelpers
  def create_entity(params), do: PipelineConfigs.create_pipeline_config(params)
  @impl GallformersWeb.Admin.FormHelpers
  def update_entity(entity, params), do: PipelineConfigs.update_pipeline_config(entity, params)
  @impl GallformersWeb.Admin.FormHelpers
  def delete_entity(entity), do: PipelineConfigs.delete_pipeline_config(entity)

  @impl GallformersWeb.Admin.FormHelpers
  def prepare_params(params) do
    config = build_config_from_params(params)

    params
    |> Map.drop(~w(client llm_clean metadata data_extract))
    |> Map.put("config", config)
  end

  @impl true
  def mount(_params, session, socket) do
    {:ok, init_admin_form(socket, session, page_title: "Pipeline Config")}
  end

  def close_form(socket), do: push_navigate(socket, to: list_path())

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> apply_new_action()
    |> assign(:config_fields, default_config_fields())
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> apply_edit_action(id)
    |> assign_config_fields_from_entity()
  end

  @impl true
  def handle_event("validate", params, socket) do
    socket =
      socket
      |> assign(:config_fields, extract_config_fields(params))
      |> mark_dirty()

    entity_params = prepare_params(Map.get(params, form_key(), %{}))
    entity = Map.get(socket.assigns, entity_key())

    changeset =
      entity
      |> change_entity(entity_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: form_key()))}
  end

  @impl true
  def handle_event("save", params, socket), do: handle_save(params, socket)

  @impl true
  def handle_event("delete", params, socket), do: handle_delete(params, socket)

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(request_cancel cancel_discard confirm_discard) do
    handle_form_event(event, params, socket)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <:page_title_html>
        <%= if @mode == :edit do %>
          Editing <em class="font-bold">{@pipeline_config.name}</em>
        <% else %>
          New Pipeline Config
        <% end %>
      </:page_title_html>
      <Layouts.admin_edit_layout
        back_path={~p"/admin/pipeline-configs"}
        back_label="Back to Pipeline Configs"
      >
        <.form for={@form} id="pipeline-config-form" phx-change="validate" phx-submit="save">
          <div class="space-y-6">
            <div class="mb-3">
              <.input
                field={@form[:name]}
                type="text"
                label="Config Name"
                placeholder="e.g. default, fast-deepseek, local-lmstudio"
              />
            </div>

            <.config_section title="Client Settings" id="client">
              <.config_field
                name="pipeline_config[client][api_url]"
                label="API URL"
                type="text"
                value={@config_fields["client"]["api_url"]}
                placeholder="https://api.deepinfra.com/v1/openai/chat/completions"
              />
              <.config_field
                name="pipeline_config[client][receive_timeout]"
                label="Receive Timeout (ms)"
                type="number"
                value={@config_fields["client"]["receive_timeout"]}
                placeholder="120000"
              />
              <.config_field
                name="pipeline_config[client][retry_backoffs]"
                label="Retry Backoffs (ms, comma-separated)"
                type="text"
                value={format_list(@config_fields["client"]["retry_backoffs"])}
                placeholder="1000, 2000, 4000"
              />
            </.config_section>

            <.config_section title="LLM Clean Stage" id="llm_clean">
              <.config_field
                name="pipeline_config[llm_clean][model]"
                label="Model"
                type="text"
                value={@config_fields["llm_clean"]["model"]}
                placeholder="deepseek-ai/DeepSeek-V3-0324"
              />
              <.config_field
                name="pipeline_config[llm_clean][chunk_size]"
                label="Chunk Size (chars)"
                type="number"
                value={@config_fields["llm_clean"]["chunk_size"]}
                placeholder="6000"
              />
              <.config_field
                name="pipeline_config[llm_clean][max_tokens]"
                label="Max Tokens"
                type="number"
                value={@config_fields["llm_clean"]["max_tokens"]}
                placeholder="8192"
              />
              <.config_field
                name="pipeline_config[llm_clean][max_concurrency]"
                label="Max Concurrency"
                type="number"
                value={@config_fields["llm_clean"]["max_concurrency"]}
                placeholder="2"
              />
              <.config_field
                name="pipeline_config[llm_clean][task_timeout_minutes]"
                label="Task Timeout (minutes)"
                type="number"
                value={@config_fields["llm_clean"]["task_timeout_minutes"]}
                placeholder="10"
              />
            </.config_section>

            <.config_section title="Metadata Stage" id="metadata">
              <.config_field
                name="pipeline_config[metadata][model]"
                label="Model"
                type="text"
                value={@config_fields["metadata"]["model"]}
                placeholder="deepseek-ai/DeepSeek-V3-0324"
              />
              <.config_field
                name="pipeline_config[metadata][max_tokens]"
                label="Max Tokens"
                type="number"
                value={@config_fields["metadata"]["max_tokens"]}
                placeholder="1024"
              />
              <.config_field
                name="pipeline_config[metadata][max_input_chars]"
                label="Max Input Chars"
                type="number"
                value={@config_fields["metadata"]["max_input_chars"]}
                placeholder="24000"
              />
            </.config_section>

            <.config_section title="Data Extract Stage" id="data_extract">
              <.config_field
                name="pipeline_config[data_extract][model]"
                label="Model"
                type="text"
                value={@config_fields["data_extract"]["model"]}
                placeholder="deepseek-ai/DeepSeek-V3-0324"
              />
              <.config_field
                name="pipeline_config[data_extract][chunk_size]"
                label="Chunk Size (chars)"
                type="number"
                value={@config_fields["data_extract"]["chunk_size"]}
                placeholder="3000"
              />
              <.config_field
                name="pipeline_config[data_extract][max_tokens]"
                label="Max Tokens"
                type="number"
                value={@config_fields["data_extract"]["max_tokens"]}
                placeholder="6000"
              />
              <.config_field
                name="pipeline_config[data_extract][max_concurrency]"
                label="Max Concurrency"
                type="number"
                value={@config_fields["data_extract"]["max_concurrency"]}
                placeholder="2"
              />
              <.config_field
                name="pipeline_config[data_extract][task_timeout_minutes]"
                label="Task Timeout (minutes)"
                type="number"
                value={@config_fields["data_extract"]["task_timeout_minutes"]}
                placeholder="10"
              />
              <.config_field
                name="pipeline_config[data_extract][json_attempts]"
                label="JSON Parse Attempts"
                type="number"
                value={@config_fields["data_extract"]["json_attempts"]}
                placeholder="3"
              />
            </.config_section>

            <div class="flex justify-between pt-4 border-t border-gray-200">
              <div>
                <button
                  :if={@mode == :edit}
                  type="button"
                  phx-click="delete"
                  data-confirm="Are you sure? Ingestions using this config will lose their config reference."
                  class="gf-btn gf-btn-danger"
                >
                  Delete
                </button>
              </div>
              <.form_actions form_dirty={@form_dirty} mode={@mode} create_label="Create Config" />
            </div>
          </div>
        </.form>

        <.discard_confirm_modal show={@show_discard_confirm} />
      </Layouts.admin_edit_layout>
    </Layouts.admin>
    """
  end

  attr :title, :string, required: true
  attr :id, :string, required: true
  slot :inner_block, required: true

  defp config_section(assigns) do
    ~H"""
    <div class="rounded-lg border border-gray-200 bg-gray-50 p-4">
      <h3 class="mb-3 text-sm font-semibold text-gray-700">{@title}</h3>
      <div class="grid gap-3 sm:grid-cols-2">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :type, :string, required: true
  attr :value, :any, default: nil
  attr :placeholder, :string, default: nil

  defp config_field(assigns) do
    ~H"""
    <div>
      <label class="block text-xs font-medium text-gray-600 mb-1">{@label}</label>
      <input
        type={@type}
        name={@name}
        value={@value}
        placeholder={@placeholder}
        class="w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-gf-maroon focus:ring-gf-maroon"
      />
    </div>
    """
  end

  defp default_config_fields do
    %{
      "client" => %{"api_url" => "", "receive_timeout" => "", "retry_backoffs" => ""},
      "llm_clean" => %{
        "model" => "",
        "chunk_size" => "",
        "max_tokens" => "",
        "max_concurrency" => "",
        "task_timeout_minutes" => ""
      },
      "metadata" => %{"model" => "", "max_tokens" => "", "max_input_chars" => ""},
      "data_extract" => %{
        "model" => "",
        "chunk_size" => "",
        "max_tokens" => "",
        "max_concurrency" => "",
        "task_timeout_minutes" => "",
        "json_attempts" => ""
      }
    }
  end

  defp assign_config_fields_from_entity(socket) do
    case socket.assigns do
      %{pipeline_config: %PipelineConfig{config: config}} when is_map(config) ->
        fields = deep_merge(default_config_fields(), stringify_values(config))
        assign(socket, :config_fields, fields)

      _ ->
        assign(socket, :config_fields, default_config_fields())
    end
  end

  defp extract_config_fields(params) do
    form_params = Map.get(params, form_key(), %{})

    %{
      "client" => Map.get(form_params, "client", %{}),
      "llm_clean" => Map.get(form_params, "llm_clean", %{}),
      "metadata" => Map.get(form_params, "metadata", %{}),
      "data_extract" => Map.get(form_params, "data_extract", %{})
    }
    |> then(&deep_merge(default_config_fields(), &1))
  end

  defp build_config_from_params(params) do
    %{
      "client" =>
        build_section(Map.get(params, "client", %{}), [
          {"api_url", :string},
          {"receive_timeout", :integer},
          {"retry_backoffs", :int_list}
        ]),
      "llm_clean" =>
        build_section(Map.get(params, "llm_clean", %{}), [
          {"model", :string},
          {"chunk_size", :integer},
          {"max_tokens", :integer},
          {"max_concurrency", :integer},
          {"task_timeout_minutes", :integer}
        ]),
      "metadata" =>
        build_section(Map.get(params, "metadata", %{}), [
          {"model", :string},
          {"max_tokens", :integer},
          {"max_input_chars", :integer}
        ]),
      "data_extract" =>
        build_section(Map.get(params, "data_extract", %{}), [
          {"model", :string},
          {"chunk_size", :integer},
          {"max_tokens", :integer},
          {"max_concurrency", :integer},
          {"task_timeout_minutes", :integer},
          {"json_attempts", :integer}
        ])
    }
    |> reject_empty_sections()
  end

  defp build_section(section_params, field_specs) when is_map(section_params) do
    field_specs
    |> Enum.reduce(%{}, fn {key, type}, acc ->
      case parse_field(Map.get(section_params, key, ""), type) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp build_section(_section_params, _field_specs), do: %{}

  defp parse_field("", _type), do: nil
  defp parse_field(nil, _type), do: nil

  defp parse_field(value, :string) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp parse_field(value, :integer) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_field(value, :int_list) do
    values =
      value
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&Integer.parse/1)

    if Enum.all?(values, &match?({_, ""}, &1)) do
      Enum.map(values, fn {int, ""} -> int end)
    else
      nil
    end
  end

  defp reject_empty_sections(config) do
    config
    |> Enum.reject(fn {_k, v} -> v == %{} end)
    |> Map.new()
  end

  defp stringify_values(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_map(v) -> {k, stringify_values(v)}
      {k, v} when is_list(v) -> {k, v}
      {k, v} -> {k, to_string(v)}
    end)
  end

  defp deep_merge(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override, fn
      _k, base_val, override_val when is_map(base_val) and is_map(override_val) ->
        deep_merge(base_val, override_val)

      _k, _base_val, override_val ->
        override_val
    end)
  end

  defp format_list(value) when is_list(value), do: Enum.join(value, ", ")
  defp format_list(value), do: value
end
