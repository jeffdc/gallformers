defmodule GallformersWeb.UserProfileLive do
  @moduledoc """
  Public user profile page.

  Displays a user's public profile information including their display name,
  about me text, and profile links. Shows an edit button if the logged-in user
  is viewing their own profile.
  """

  use GallformersWeb, :live_view

  alias Gallformers.Accounts

  @impl true
  def mount(%{"nickname" => nickname}, session, socket) do
    current_user = session["current_user"]

    case Accounts.get_user_by_nickname(nickname) do
      nil ->
        {:ok,
         socket
         |> assign(:current_user, current_user)
         |> assign(:page_title, "User Not Found")
         |> assign(:user, nil)}

      user ->
        {:ok,
         socket
         |> assign(:current_user, current_user)
         |> assign(:page_title, display_name(user))
         |> assign(:page_description, user.about_me)
         |> assign(:user, user)
         |> assign(:own_profile, own_profile?(current_user, user))}
    end
  end

  defp own_profile?(nil, _user), do: false

  defp own_profile?(current_user, user) do
    current_user.id == user.auth0_id
  end

  defp display_name(user) do
    cond do
      user.display_name && user.display_name != "" -> user.display_name
      user.nickname && user.nickname != "" -> user.nickname
      true -> "Anonymous"
    end
  end

  defp has_links?(user) do
    (user.inaturalist_url && user.inaturalist_url != "") ||
      (user.social_url && user.social_url != "") ||
      (user.personal_url && user.personal_url != "")
  end

  # Social platform patterns: {match_strings, icon, label}
  @social_platforms [
    {["twitter.com", "x.com"], "ph-x-logo", "X"},
    {["facebook.com"], "ph-facebook-logo", "Facebook"},
    {["instagram.com"], "ph-instagram-logo", "Instagram"},
    {["linkedin.com"], "ph-linkedin-logo", "LinkedIn"},
    {["youtube.com", "youtu.be"], "ph-youtube-logo", "YouTube"},
    {["bsky.app", "bluesky"], "ph-butterfly", "Bluesky"},
    {["mastodon", "fosstodon", "mstdn"], "ph-mastodon-logo", "Mastodon"}
  ]

  @default_social {"ph-chat-circle", "Social"}

  # Detect social media platform from URL and return {icon, label}
  defp social_platform(url) when is_binary(url) do
    url_lower = String.downcase(url)

    Enum.find_value(@social_platforms, @default_social, fn {patterns, icon, label} ->
      if Enum.any?(patterns, &String.contains?(url_lower, &1)), do: {icon, label}
    end)
  end

  defp social_platform(_), do: @default_social

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <%= if @user do %>
        <div class="max-w-2xl mx-auto">
          <div class="bg-surface rounded-panel border border-line p-6">
            <%!-- Header with name and edit button --%>
            <div class="flex items-center justify-between mb-4">
              <h1 class="text-section font-bold text-brand">
                {display_name(@user)}
              </h1>
              <%= if @own_profile do %>
                <a
                  href="/admin/profile"
                  class="flex items-center gap-1 text-meta hover:underline"
                  title="Edit profile"
                >
                  <.icon name="ph-pencil-simple" class="h-4 w-4" /> Edit
                </a>
              <% end %>
            </div>

            <%!-- About Me --%>
            <%= if @user.about_me && @user.about_me != "" do %>
              <div class="mb-6">
                <p class="text-ink-2 whitespace-pre-wrap">{@user.about_me}</p>
              </div>
            <% end %>

            <%!-- Profile Links --%>
            <%= if has_links?(@user) do %>
              <div class="flex flex-wrap items-center gap-4">
                <%= if @user.inaturalist_url && @user.inaturalist_url != "" do %>
                  <a
                    href={@user.inaturalist_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    title="iNaturalist profile"
                    class="hover:opacity-80 transition-opacity"
                  >
                    <img
                      src="/images/inatlogo-small.png"
                      alt="iNaturalist"
                      class="h-6"
                    />
                  </a>
                <% end %>
                <% {social_icon, social_label} = social_platform(@user.social_url) %>
                <%= if @user.social_url && @user.social_url != "" do %>
                  <a
                    href={@user.social_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="inline-flex items-center gap-1 text-brand hover:underline"
                  >
                    <.icon name={social_icon} class="h-5 w-5" /> {social_label}
                  </a>
                <% end %>
                <%= if @user.personal_url && @user.personal_url != "" do %>
                  <a
                    href={@user.personal_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="inline-flex items-center gap-1 text-brand hover:underline"
                  >
                    <.icon name="ph-globe" class="h-5 w-5" /> Website
                  </a>
                <% end %>
              </div>
            <% end %>

            <%!-- Empty state if no about_me and no links --%>
            <%= if (!@user.about_me || @user.about_me == "") && !has_links?(@user) do %>
              <p class="text-muted italic">This user hasn't added any profile information yet.</p>
            <% end %>
          </div>
        </div>
      <% else %>
        <div class="max-w-2xl mx-auto">
          <div class="bg-surface rounded-panel border border-line p-6 text-center">
            <h1 class="text-section font-bold text-ink-2 mb-2">User Not Found</h1>
            <p class="text-muted">The user you're looking for doesn't exist.</p>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
