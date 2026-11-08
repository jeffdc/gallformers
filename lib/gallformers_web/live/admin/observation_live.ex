defmodule GallformersWeb.Admin.ObservationLive do
  @moduledoc """
  Add from observation with no Gall given (`/admin/observation`; the
  command palette's "Add from observation…"; matter `87a1`, its question
  9): one field. Reading the observation
  (`Gallformers.Curation.from_observation/3`) opens the Gall it suggests
  (the only Gall of its taxon, or the one its "Gallformers Code" field
  names) in Edit mode, with the Fact inspector on the observation
  (`/gall/:id?edit&observation=<id>`, `GallformersWeb.GallLive.FromObservation`).
  With several Galls they are listed to choose; with none it says so.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Curation

  @impl true
  def mount(_params, _session, socket),
    do:
      {:ok,
       assign(socket, page_title: "Add from observation", url: "", error: nil, proposal: nil)}

  @impl true
  def handle_event("read", %{"url" => url}, socket) do
    case Curation.from_observation(socket.assigns.actor, String.trim(url), nil) do
      {:ok, %{gall: %{gall_id: id}, observation: %{id: obs_id}}} when is_integer(id) ->
        {:noreply, push_navigate(socket, to: gall_path(id, obs_id))}

      {:ok, proposal} ->
        {:noreply, assign(socket, url: url, error: nil, proposal: proposal)}

      {:error, reason} ->
        {:noreply, assign(socket, url: url, error: error_text(reason), proposal: nil)}
    end
  end

  defp gall_path(gall_id, obs_id), do: "/gall/#{gall_id}?edit&observation=#{obs_id}"

  defp error_text(:invalid_input), do: "That isn't an iNaturalist observation's link or number."
  defp error_text(:not_found), do: "iNaturalist has no such observation."
  defp error_text(:unavailable), do: "iNaturalist couldn't be reached. Try again in a moment."
  defp error_text(_reason), do: "The observation couldn't be read."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-block">
        <.page_header>
          <:title>Add from observation</:title>
          <:description>
            Read an iNaturalist observation: its Gall's page opens in Edit mode with what the observation shows, for your tray.
          </:description>
        </.page_header>

        <div class="flex max-w-form flex-col gap-block">
          <form id="observation-form" phx-submit="read" class="flex items-end gap-2">
            <div class="flex-1">
              <.input
                type="text"
                name="url"
                value={@url}
                label="iNaturalist observation"
                placeholder="A link or its number"
              />
            </div>
            <.button type="submit">Read</.button>
          </form>
          <p :if={@error} data-part="error" class="text-meta text-danger">{@error}</p>

          <div :if={@proposal && @proposal.gall.candidates != []} id="observation-galls">
            <p class="text-ui text-ink-2">
              Gallformers has {length(@proposal.gall.candidates)} Galls of
              <.taxon_name name={@proposal.observation.taxon_name} />. Which one is it?
            </p>
            <ul class="mt-2 flex flex-col gap-1">
              <li :for={gall <- @proposal.gall.candidates}>
                <.link navigate={gall_path(gall.id, @proposal.observation.id)}>
                  <.gall_name name={gall.name} />
                </.link>
              </li>
            </ul>
          </div>

          <p
            :if={@proposal && @proposal.gall.candidates == []}
            id="observation-none"
            class="text-ui text-ink-2"
          >
            No Gall in Gallformers is of
            <.taxon_name name={@proposal.observation.taxon_name || "the observation's taxon"} />.
            Open the Gall's page and use Add from observation… there.
          </p>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
