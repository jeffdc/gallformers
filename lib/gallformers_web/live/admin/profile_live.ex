defmodule GallformersWeb.Admin.ProfileLive do
  @moduledoc """
  LiveView for admins to edit their own profile.

  Displays and allows editing of:
  - Display name (editable)
  - Nickname (read-only, synced from Auth0)
  - About me bio text
  - iNaturalist URL
  - Social media URL
  - Personal website URL
  - About page visibility toggle
  """

  use GallformersWeb, :live_view
  use GallformersWeb.Admin.FormHelpers

  import GallformersWeb.Admin.FormComponents, only: [form_actions: 1]

  alias Gallformers.Accounts
  alias Gallformers.Accounts.User

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "My Profile")
      |> assign(:mode, :edit)
      |> init_form_state()
      |> load_user_profile()

    {:ok, socket}
  end

  defp load_user_profile(socket) do
    auth0_user = socket.assigns.current_user

    case Accounts.get_user_by_auth0_id(auth0_user.id) do
      nil ->
        # Profile doesn't exist - create it now using Auth0 data from session
        case Accounts.sync_user_from_auth0(auth0_user) do
          {:ok, user} ->
            changeset = User.update_changeset(user, %{})

            socket
            |> put_flash(:info, "Profile created successfully. Welcome!")
            |> assign(:user, user)
            |> assign(:form, to_form(changeset))
            |> assign(:inat_username, extract_inat_username(user.inaturalist_url))

          {:error, _changeset} ->
            socket
            |> put_flash(:error, "Unable to create your profile. Please contact support.")
            |> assign(:user, nil)
            |> assign(:form, nil)
        end

      %User{} = user ->
        changeset = User.update_changeset(user, %{})

        socket
        |> assign(:user, user)
        |> assign(:form, to_form(changeset))
        |> assign(:inat_username, extract_inat_username(user.inaturalist_url))
    end
  end

  @inat_url_pattern ~r{^https?://(?:www\.)?inaturalist\.org/people/([^/\s?]+)}

  defp extract_inat_username(nil), do: ""
  defp extract_inat_username(""), do: ""

  defp extract_inat_username(url) do
    case Regex.run(@inat_url_pattern, url) do
      [_, username] -> username
      _ -> ""
    end
  end

  defp build_inat_url(""), do: nil
  defp build_inat_url(nil), do: nil
  defp build_inat_url(username), do: "https://www.inaturalist.org/people/#{username}"

  def close_form(socket) do
    push_navigate(socket, to: ~p"/admin")
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    # Handle inat_username separately - it's not a real form field
    inat_username = Map.get(user_params, "inat_username", socket.assigns.inat_username)

    # Convert username to URL for the changeset
    user_params = Map.put(user_params, "inaturalist_url", build_inat_url(inat_username))

    changeset =
      socket.assigns.user
      |> User.update_changeset(user_params)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:form, to_form(changeset))
      |> assign(:inat_username, inat_username)
      |> mark_dirty()

    {:noreply, socket}
  end

  # Catch-all for validate events that don't match the expected form structure
  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    # Convert inat_username to URL
    inat_username = Map.get(user_params, "inat_username", "")
    user_params = Map.put(user_params, "inaturalist_url", build_inat_url(inat_username))

    case Accounts.update_user(socket.assigns.user, user_params) do
      {:ok, _user} ->
        # Redirect through refresh-session to update session with new display_name
        {:noreply, redirect(socket, to: "/admin/refresh-session?return_to=/admin/profile")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

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
          <:crumb navigate={~p"/admin"}>Dashboard</:crumb>
          <:title>Your profile</:title>
          <:description>
            Your display name is shown, publicly, wherever a change is credited. Your About blurb and links appear on the About page if you choose to be listed there.
          </:description>
          <:action :if={@user && @user.nickname}>
            <.button
              href={~p"/user/#{@user.nickname}"}
              target="_blank"
              variant="ghost"
              size="sm"
              icon="ph-arrow-square-out"
            >
              View on site
            </.button>
          </:action>
        </.page_header>

        <.notice :if={!@form} kind={:danger}>
          Your profile couldn't be created or loaded. If this keeps happening, ask in Discord.
        </.notice>

        <div :if={@form} class="gf-with-rail">
          <.form
            for={@form}
            id="profile-form"
            phx-change="validate"
            phx-submit="save"
            class="flex max-w-form min-w-0 flex-col gap-block"
          >
            <.input
              field={@form[:display_name]}
              type="text"
              label="Display name"
              placeholder="How you want to be known"
              required
            />
            <.input
              field={@form[:about_me]}
              type="textarea"
              label="About me"
              rows="4"
              placeholder="A few words about yourself"
            />
            <div>
              <label class="gf-label" for="profile-inat">iNaturalist username</label>
              <div class="flex">
                <span class="flex shrink-0 items-center whitespace-nowrap rounded-l-ctl border border-r-0 border-line-strong bg-surface-2 px-3 text-meta text-muted">
                  inaturalist.org/people/
                </span>
                <input
                  id="profile-inat"
                  type="text"
                  name="user[inat_username]"
                  value={@inat_username}
                  placeholder="yourusername"
                  class="gf-input min-w-0 flex-1 rounded-l-none"
                />
              </div>
              <p class="gf-hint">Just the username, not the whole address.</p>
            </div>
            <div>
              <label class="gf-label" for="profile-social">Social media</label>
              <input
                id="profile-social"
                type="url"
                name={@form[:social_url].name}
                value={Phoenix.HTML.Form.input_value(@form, :social_url)}
                placeholder="https://bsky.app/profile/youruserprofile"
                class="gf-input"
              />
            </div>
            <div>
              <label class="gf-label" for="profile-website">Website</label>
              <input
                id="profile-website"
                type="url"
                name={@form[:personal_url].name}
                value={Phoenix.HTML.Form.input_value(@form, :personal_url)}
                placeholder="https://yourwebsite.com"
                class="gf-input"
              />
            </div>
            <.input type="checkbox" field={@form[:show_on_about]} label="List me on the About page" />

            <div class="flex justify-end border-t border-line pt-block">
              <.form_actions form_dirty={@form_dirty} mode={@mode} />
            </div>
          </.form>

          <.rail width={:narrow}>
            <.panel id="account" title="Your account">
              <dl class="flex flex-col gap-1 text-ui">
                <dt class="text-meta text-muted">Nickname</dt>
                <dd class="text-ink">{@current_user.nickname || "Not set"}</dd>
              </dl>
              <p class="gf-hint">From your Auth0 account; it can't be changed here.</p>
              <a
                href={Accounts.password_reset_url()}
                target="_blank"
                rel="noopener noreferrer"
                class="mt-3 inline-flex items-center gap-1 text-ui"
              >
                Reset your password <.icon name="ph-arrow-square-out" class="size-4" />
              </a>
            </.panel>
          </.rail>
        </div>

        <.discard_confirm_modal :if={@form} show={@show_discard_confirm} />
      </div>
    </Layouts.admin>
    """
  end
end
