defmodule GallformersWeb.Admin.ObservationLive do
  @moduledoc """
  Add from observation, from anywhere (`/admin/observation`; the command
  palette's "Add from observation…", matter `ec2c`): one iNaturalist
  observation read into proposals for the curator's tray, the Gall chosen
  (`GallformersWeb.ObservationIntake`). On a Gall's own page, Edit mode
  opens the same with the Gall given.
  """
  use GallformersWeb, :live_view

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: "Add from observation")}

  # Photos imported: they show on the Gall's page.
  @impl true
  def handle_info({:inat_import_complete, _owner}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-block">
        <.page_header>
          <:title>Add from observation</:title>
          <:description>
            Read an iNaturalist observation into your tray: where and when the Gall was seen, and
            the Host it was on, each with the observation as its evidence. Nothing changes until
            you Review and apply.
          </:description>
        </.page_header>

        <div class="max-w-form">
          <.live_component
            module={GallformersWeb.ObservationIntake}
            id="observation-intake"
            curator={@actor}
            gall={nil}
          />
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
