defmodule GallformersWeb.Admin.ArticleLive.Form do
  @moduledoc """
  Admin form for creating and editing reference articles.

  Features:
  - Edit/Preview tabs with markdown rendering
  - Tag management
  - Image upload and browser integration
  """

  use GallformersWeb, :live_view
  use GallformersWeb.Admin.FormHelpers

  require Logger

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Articles
  alias Gallformers.Articles.Article
  alias Gallformers.Markdown
  alias Gallformers.Storage

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]
    all_tags = Articles.list_all_tags()
    article_options = Articles.list_article_options()

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Article")
      |> init_form_state()
      |> assign(:all_tags, all_tags)
      |> assign(:article_options, article_options)
      |> assign(:preview_content, nil)
      |> assign(:active_tab, :edit)
      |> assign(:show_image_browser, false)
      |> assign(:article_images, [])
      |> assign(:image_browser_filter, "")
      # Image insert modal state
      |> assign(:show_image_insert_modal, false)
      |> assign(:selected_image, nil)
      |> assign(:image_insert_form, nil)
      # Image delete confirmation state
      |> assign(:image_to_delete, nil)
      |> assign(:image_references, [])
      # Tag dropdown state
      |> assign(:form_tags, [])
      |> assign(:tag_search_query, "")
      |> assign(:tag_dropdown_open, false)

    {:ok, socket}
  end

  def close_form(socket) do
    push_navigate(socket, to: ~p"/admin/articles")
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    # Pre-populate author from logged in user
    author = Auth0User.display_name(socket.assigns.current_user)
    article = %Article{author: author}
    changeset = Articles.change_article(article, %{author: author})

    socket
    |> assign(:page_title, "New Article")
    |> assign(:article, article)
    |> assign(:form, to_form(changeset))
    |> assign(:mode, :new)
    |> assign(:preview_content, nil)
    |> assign(:form_tags, [])
    |> reset_dirty()
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    case safe_load_article(id) do
      nil ->
        socket
        |> put_flash(:error, "Article not found")
        |> push_navigate(to: ~p"/admin/articles")

      article ->
        changeset = Articles.change_article(article)

        socket
        |> assign(:page_title, "Edit Article")
        |> assign(:article, article)
        |> assign(:form, to_form(changeset))
        |> assign(:mode, :edit)
        |> assign(:preview_content, render_preview(article.content))
        |> assign(:form_tags, article.tags)
        |> reset_dirty()
    end
  end

  defp safe_load_article(id) do
    Articles.get_article!(String.to_integer(id))
  rescue
    Ecto.NoResultsError -> nil
  end

  @impl true
  def handle_event("validate", %{"article" => params}, socket) do
    article = socket.assigns.article
    # Include current form_tags in params for validation
    params_with_tags = Map.put(params, "tags", socket.assigns.form_tags)

    changeset =
      article
      |> Articles.change_article(normalize_params(params_with_tags))
      |> Map.put(:action, :validate)

    preview_content = render_preview(params["content"])

    socket =
      socket
      |> assign(:form, to_form(changeset))
      |> mark_dirty()
      |> assign(:preview_content, preview_content)

    {:noreply, socket}
  end

  # Catch-all for validate events that don't match the expected form structure
  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"article" => params}, socket) do
    article = socket.assigns.article
    # Include current form_tags in params
    params_with_tags = Map.put(params, "tags", socket.assigns.form_tags)
    params = normalize_params(params_with_tags)

    result =
      if socket.assigns.mode == :edit do
        Articles.update_article(article, params)
      else
        Articles.create_article(params)
      end

    case result do
      {:ok, saved_article} ->
        socket =
          socket
          |> put_flash(
            :info,
            if(socket.assigns.mode == :edit, do: "Article updated.", else: "Article created.")
          )
          |> push_navigate(to: ~p"/admin/articles/#{saved_article.id}")

        {:noreply, socket}

      {:error, changeset} ->
        socket =
          socket
          |> assign(:form, to_form(changeset))
          |> put_flash(:error, "Failed to save article. Check the form for errors.")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case Articles.delete_article(socket.assigns.article) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Article deleted successfully")
         |> push_navigate(to: ~p"/admin/articles")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete article")}
    end
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(request_cancel cancel_discard confirm_discard) do
    # Handle image browser panels first
    cond do
      event == "request_cancel" and socket.assigns.image_to_delete != nil ->
        {:noreply,
         socket
         |> assign(:image_to_delete, nil)
         |> assign(:image_references, [])}

      event == "request_cancel" and socket.assigns.show_image_insert_modal ->
        {:noreply,
         socket
         |> assign(:show_image_insert_modal, false)
         |> assign(:selected_image, nil)
         |> assign(:image_insert_form, nil)}

      event == "request_cancel" and socket.assigns.show_image_browser ->
        {:noreply, assign(socket, :show_image_browser, false)}

      true ->
        handle_form_event(event, params, socket)
    end
  end

  @valid_tabs ~w(edit preview)

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in @valid_tabs do
    {:noreply, assign(socket, :active_tab, String.to_atom(tab))}
  end

  # Tag dropdown event handlers
  @impl true
  def handle_event("tag_search", %{"value" => value}, socket) do
    {:noreply, assign(socket, :tag_search_query, value)}
  end

  @impl true
  def handle_event("open_tag_dropdown", _params, socket) do
    {:noreply, assign(socket, :tag_dropdown_open, true)}
  end

  @impl true
  def handle_event("close_tag_dropdown", _params, socket) do
    # If the user typed a new tag that doesn't exist, add it
    search_query = String.trim(socket.assigns.tag_search_query)
    form_tags = socket.assigns.form_tags

    socket =
      if search_query != "" and search_query not in form_tags do
        socket
        |> assign(:form_tags, form_tags ++ [search_query])
        |> mark_dirty()
      else
        socket
      end

    socket =
      socket
      |> assign(:tag_dropdown_open, false)
      |> assign(:tag_search_query, "")

    {:noreply, socket}
  end

  @impl true
  def handle_event("add_tag", %{"id" => tag}, socket) do
    form_tags = socket.assigns.form_tags

    socket =
      if tag in form_tags do
        socket
      else
        socket
        |> assign(:form_tags, form_tags ++ [tag])
        |> mark_dirty()
      end

    {:noreply, assign(socket, :tag_search_query, "")}
  end

  @impl true
  def handle_event("remove_tag", %{"id" => tag}, socket) do
    form_tags = Enum.reject(socket.assigns.form_tags, &(&1 == tag))

    {:noreply,
     socket
     |> assign(:form_tags, form_tags)
     |> mark_dirty()}
  end

  # Image browser event handlers
  @impl true
  def handle_event("open_image_browser", _params, socket) do
    # Default to current article's images if editing an article
    article = socket.assigns.article

    {images, filter} =
      if article && article.id do
        {Storage.list_article_images_for_article(article.id), article.id}
      else
        {Storage.list_article_images(), ""}
      end

    {:noreply,
     socket
     |> assign(:article_images, images)
     |> assign(:image_browser_filter, filter)
     |> assign(:show_image_browser, true)}
  end

  @impl true
  def handle_event("close_image_browser", _params, socket) do
    {:noreply, assign(socket, :show_image_browser, false)}
  end

  @impl true
  def handle_event("filter_images_by_article", %{"article_id" => ""}, socket) do
    images = Storage.list_article_images()

    {:noreply,
     socket
     |> assign(:article_images, images)
     |> assign(:image_browser_filter, "")}
  end

  @impl true
  def handle_event("filter_images_by_article", %{"article_id" => article_id}, socket) do
    article_id = String.to_integer(article_id)
    images = Storage.list_article_images_for_article(article_id)

    {:noreply,
     socket
     |> assign(:article_images, images)
     |> assign(:image_browser_filter, article_id)}
  end

  @impl true
  def handle_event("select_image", %{"url" => url, "name" => name}, socket) do
    selected_image = %{url: url, name: name}

    form =
      to_form(%{
        "alt_text" => "",
        "caption" => "",
        "size_preset" => "medium",
        "custom_width" => ""
      })

    socket =
      socket
      |> assign(:selected_image, selected_image)
      |> assign(:image_insert_form, form)
      |> assign(:show_image_insert_modal, true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_image_insert", params, socket) do
    form = to_form(params)
    {:noreply, assign(socket, :image_insert_form, form)}
  end

  @impl true
  def handle_event("close_image_insert_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_image_insert_modal, false)
     |> assign(:selected_image, nil)
     |> assign(:image_insert_form, nil)}
  end

  @impl true
  def handle_event("insert_image", params, socket) do
    alt_text = String.trim(params["alt_text"] || "")

    if alt_text == "" do
      {:noreply, put_flash(socket, :error, "Alt text is required for accessibility")}
    else
      {:noreply, do_insert_image(socket, params, alt_text)}
    end
  end

  # Image delete confirmation
  @impl true
  def handle_event(
        "confirm_delete_image",
        %{"url" => url, "path" => path, "name" => name},
        socket
      ) do
    references = Articles.find_articles_referencing_image(url)
    image_to_delete = %{url: url, path: path, name: name}

    {:noreply,
     socket
     |> assign(:image_to_delete, image_to_delete)
     |> assign(:image_references, references)}
  end

  @impl true
  def handle_event("cancel_delete_image", _params, socket) do
    {:noreply,
     socket
     |> assign(:image_to_delete, nil)
     |> assign(:image_references, [])}
  end

  @impl true
  def handle_event("delete_image", _params, socket) do
    image = socket.assigns.image_to_delete
    Logger.info("Deleting image: path=#{inspect(image.path)}, url=#{inspect(image.url)}")

    case Storage.delete_article_image(image.path) do
      :ok ->
        # Refresh the image list
        images =
          case socket.assigns.image_browser_filter do
            "" -> Storage.list_article_images()
            article_id -> Storage.list_article_images_for_article(article_id)
          end

        {:noreply,
         socket
         |> assign(:article_images, images)
         |> assign(:image_to_delete, nil)
         |> assign(:image_references, [])
         |> put_flash(:info, "Image deleted.")}

      {:error, reason} ->
        Logger.error(
          "Failed to delete image: path=#{inspect(image.path)}, reason=#{inspect(reason)}"
        )

        error_message = format_s3_error(reason)

        {:noreply,
         socket
         |> assign(:image_to_delete, nil)
         |> assign(:image_references, [])
         |> put_flash(:error, error_message)}
    end
  end

  # Image upload handlers
  @impl true
  def handle_event("request_article_image_url", %{"extension" => ext, "type" => type}, socket) do
    article = socket.assigns.article

    if article && article.id do
      path = Storage.generate_article_path(article.id, ext)

      case Storage.presigned_upload_url(path, type) do
        {:ok, url} ->
          image_url = Storage.article_image_url(path)

          {:noreply,
           push_event(socket, "article_presigned_url", %{
             url: url,
             path: path,
             content_type: type,
             image_url: image_url
           })}

        {:error, reason} ->
          Logger.error("Failed to generate presigned URL for article image: #{inspect(reason)}")

          {:noreply,
           push_event(socket, "article_upload_error", %{
             message: "Failed to get upload URL: #{inspect(reason)}"
           })}
      end
    else
      {:noreply,
       push_event(socket, "article_upload_error", %{
         message: "Save article first before uploading images"
       })}
    end
  end

  @impl true
  def handle_event("article_image_uploaded", %{"path" => _path}, socket) do
    socket = put_flash(socket, :info, "Image uploaded and inserted at cursor!")
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_user={@current_user}
      page_title={@page_title}
      public_url={if @mode == :edit, do: ~p"/articles/#{@article.slug}"}
    >
      <Layouts.admin_edit_layout
        back_path={~p"/admin/articles"}
        back_label="Back to Articles"
        title={if @mode == :new, do: "Add New Article", else: "Edit Article"}
      >
        <:intro>
          Reference articles provide educational content about galls with markdown formatting and glossary auto-linking.
        </:intro>

        <:quick_links :if={@mode == :edit}>
          <.link
            href={~p"/articles/#{@article.slug}"}
            target="_blank"
            class="text-sm hover:underline"
          >
            View Public Page
          </.link>
        </:quick_links>

        <%= if @show_image_browser do %>
          <%!-- Image Browser (replaces edit/preview content) --%>
          <div class="flex flex-col min-h-[500px]">
            <div class="flex items-center justify-between pb-4 border-b border-gray-200">
              <div class="flex items-center gap-3">
                <button
                  type="button"
                  phx-click="close_image_browser"
                  class="text-gray-500 hover:text-gray-700"
                >
                  <.icon name="ph-arrow-left" class="h-5 w-5" />
                </button>
                <h3 class="text-lg font-semibold text-gray-900">Browse Article Images</h3>
              </div>
              <form phx-change="filter_images_by_article" id="image-article-filter" class="w-64">
                <.input
                  type="select"
                  name="article_id"
                  prompt="All Articles"
                  options={Enum.map(@article_options, fn {id, title} -> {title, id} end)}
                  value={@image_browser_filter}
                />
              </form>
            </div>

            <div class="flex-1 overflow-y-auto py-4">
              <%= cond do %>
                <% @image_to_delete != nil -> %>
                  <.image_delete_confirm
                    image={@image_to_delete}
                    references={@image_references}
                  />
                <% @show_image_insert_modal && @selected_image -> %>
                  <.image_insert_form
                    image={@selected_image}
                    form={@image_insert_form}
                  />
                <% true -> %>
                  <.image_grid
                    images={@article_images}
                    article_options={@article_options}
                    filter={@image_browser_filter}
                  />
              <% end %>
            </div>
          </div>
        <% else %>
          <%!-- Edit/Preview Tabs --%>
          <div class="border-b border-gray-200 mb-4">
            <nav class="-mb-px flex space-x-8">
              <button
                type="button"
                phx-click="switch_tab"
                phx-value-tab="edit"
                class={[
                  "py-2 px-1 border-b-2 font-medium text-sm",
                  if(@active_tab == :edit,
                    do: "border-gf-maroon text-gf-maroon",
                    else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
                  )
                ]}
              >
                Edit
              </button>
              <button
                type="button"
                phx-click="switch_tab"
                phx-value-tab="preview"
                class={[
                  "py-2 px-1 border-b-2 font-medium text-sm",
                  if(@active_tab == :preview,
                    do: "border-gf-maroon text-gf-maroon",
                    else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
                  )
                ]}
              >
                Preview
              </button>
            </nav>
          </div>

          <%= if @active_tab == :edit do %>
            <.form
              for={@form}
              id="article-form"
              phx-submit="save"
              phx-change="validate"
              class="space-y-4"
            >
              <div>
                <.input field={@form[:title]} schema={Article} label="Title" />
              </div>
              <div>
                <.input
                  field={@form[:slug]}
                  label="Slug"
                  placeholder="auto-generated from title if blank"
                />
              </div>
              <div>
                <.input field={@form[:author]} schema={Article} label="Author" />
              </div>
              <div>
                <.input
                  type="textarea"
                  field={@form[:description]}
                  label="Description"
                  placeholder="Brief summary for article previews and SEO"
                  rows={2}
                />
                <p class="mt-1 text-xs text-gray-500">
                  Optional. Used for article previews and search engine descriptions.
                </p>
              </div>
              <div>
                <label class="gf-label">
                  Content (Markdown)<span class="text-red-600 ml-0.5">*</span>
                </label>
                <textarea
                  name={@form[:content].name}
                  id={@form[:content].id}
                  class="w-full rounded-md border border-gray-300 shadow-sm focus:border-gf-maroon focus:ring-gf-maroon font-mono text-sm resize-y min-h-[300px]"
                  required
                >{Phoenix.HTML.Form.input_value(@form, :content)}</textarea>
                <div class="mt-2 flex items-center justify-between">
                  <p class="text-xs text-gray-500">
                    Supports markdown formatting. Glossary terms are auto-linked.
                  </p>
                  <%!-- Image Upload & Browse --%>
                  <%= if @article.id do %>
                    <div class="flex items-center gap-2">
                      <div
                        id="article-image-upload"
                        phx-hook="ArticleImageUpload"
                        phx-update="ignore"
                        data-content-textarea={@form[:content].id}
                        class="flex items-center gap-2"
                      >
                        <button
                          type="button"
                          data-upload-trigger
                          class="gf-btn gf-btn-secondary text-sm"
                        >
                          Upload Image
                        </button>
                        <input
                          data-file-input
                          type="file"
                          accept="image/jpeg,image/png"
                          class="hidden"
                        />
                        <span data-status class="text-sm"></span>
                      </div>
                      <button
                        type="button"
                        phx-click="open_image_browser"
                        class="gf-btn gf-btn-secondary text-sm"
                      >
                        Browse Images
                      </button>
                    </div>
                  <% else %>
                    <p class="text-xs text-gray-400">Save article first to add images</p>
                  <% end %>
                </div>
              </div>
              <div>
                <.multi_select_dropdown
                  id="article-tags"
                  label="Tags"
                  type={:tags}
                  options={Enum.map(@all_tags, fn tag -> %{id: tag, tag: tag} end)}
                  selected={Enum.map(@form_tags, fn tag -> %{id: tag, tag: tag} end)}
                  search_query={@tag_search_query}
                  dropdown_open={@tag_dropdown_open}
                  item_id={:id}
                  item_label={:tag}
                  placeholder="Select or type tags..."
                  on_search="tag_search"
                  on_add="add_tag"
                  on_remove="remove_tag"
                  on_open="open_tag_dropdown"
                  on_close="close_tag_dropdown"
                />
                <p class="mt-1 text-xs text-gray-500">
                  Select existing tags or type a new tag and press Enter
                </p>
              </div>
              <.input type="checkbox" field={@form[:is_published]} label="Published" />

              <div class="flex justify-between pt-4 border-t border-gray-200">
                <div>
                  <button
                    :if={@mode == :edit}
                    type="button"
                    phx-click="delete"
                    data-confirm="Are you sure you want to delete this article?"
                    class="gf-btn gf-btn-danger"
                  >
                    Delete
                  </button>
                </div>
                <div class="flex gap-3">
                  <button
                    type="button"
                    phx-click="request_cancel"
                    class="px-4 py-2 text-gray-700 border border-gray-300 rounded-md hover:bg-gray-50"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={not @form_dirty}
                    class={[
                      "px-4 py-2 rounded-md",
                      if(@form_dirty,
                        do: "bg-gf-maroon text-white hover:bg-gf-maroon/90",
                        else: "bg-gray-300 text-gray-500 cursor-not-allowed"
                      )
                    ]}
                  >
                    {if @mode == :edit, do: "Save Changes", else: "Create Article"}
                  </button>
                </div>
              </div>
            </.form>
          <% else %>
            <%!-- Preview Tab --%>
            <div class="prose prose-sm max-w-none border border-gray-200 rounded-md p-4 min-h-[300px]">
              <%= if @preview_content do %>
                {Phoenix.HTML.raw(@preview_content)}
              <% else %>
                <p class="text-gray-500 italic">Enter content to see preview.</p>
              <% end %>
            </div>
            <div class="flex justify-end pt-4 mt-4 border-t border-gray-200">
              <button
                type="button"
                phx-click="switch_tab"
                phx-value-tab="edit"
                class="gf-btn gf-btn-secondary"
              >
                Back to Edit
              </button>
            </div>
          <% end %>
        <% end %>

        <.discard_confirm_modal show={@show_discard_confirm} />
      </Layouts.admin_edit_layout>
    </Layouts.admin>
    """
  end

  # Image delete confirmation component
  defp image_delete_confirm(assigns) do
    ~H"""
    <div class="max-w-md mx-auto">
      <div class="bg-white rounded-lg border border-gray-200 shadow-sm">
        <div class="p-4 border-b border-gray-200">
          <h4 class="text-lg font-semibold text-gray-900">Delete Image</h4>
        </div>
        <div class="p-4 space-y-4">
          <div class="flex justify-center bg-gray-100 rounded-lg p-4">
            <img src={@image.url} alt="Image to delete" class="max-h-32 object-contain rounded" />
          </div>
          <%= if @references == [] do %>
            <p class="text-gray-600">
              Are you sure you want to delete this image? This action cannot be undone.
            </p>
          <% else %>
            <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
              <div class="flex items-start gap-2">
                <.icon name="ph-warning" class="h-5 w-5 text-yellow-600 mt-0.5" />
                <div>
                  <p class="text-yellow-800 font-medium">
                    This image is referenced in {length(@references)} article{if length(@references) !=
                                                                                   1,
                                                                                 do: "s",
                                                                                 else: ""}:
                  </p>
                  <ul class="mt-2 text-sm text-yellow-700 list-disc list-inside">
                    <li :for={{_id, title} <- @references}>{title}</li>
                  </ul>
                  <p class="mt-2 text-yellow-700 text-sm">
                    Deleting this image will break these references.
                  </p>
                </div>
              </div>
            </div>
          <% end %>
        </div>
        <div class="p-4 border-t border-gray-200 flex justify-end gap-2">
          <button
            type="button"
            phx-click="cancel_delete_image"
            class="px-4 py-2 text-gray-700 border border-gray-300 rounded-md hover:bg-gray-50"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click="delete_image"
            class="px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700"
          >
            {if @references == [], do: "Delete", else: "Delete Anyway"}
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Image insert form component
  defp image_insert_form(assigns) do
    ~H"""
    <div class="max-w-md mx-auto">
      <div class="bg-white rounded-lg border border-gray-200 shadow-sm">
        <div class="flex items-center justify-between p-4 border-b border-gray-200">
          <h4 class="text-lg font-semibold text-gray-900">Insert Image</h4>
          <button
            type="button"
            phx-click="close_image_insert_modal"
            class="text-gray-400 hover:text-gray-600"
          >
            <.icon name="ph-x" class="h-5 w-5" />
          </button>
        </div>
        <div class="p-4 space-y-4">
          <div class="flex justify-center bg-gray-100 rounded-lg p-4">
            <img src={@image.url} alt="Preview" class="max-h-48 object-contain rounded" />
          </div>
          <.form
            for={@form}
            id="image-insert-form"
            phx-submit="insert_image"
            phx-change="validate_image_insert"
            class="space-y-4"
          >
            <div>
              <.input
                field={@form[:alt_text]}
                label="Alt Text"
                placeholder="Describe the image for accessibility"
                required
              />
              <p class="mt-1 text-xs text-gray-500">
                Required. Describes the image for screen readers.
              </p>
            </div>
            <div>
              <.input
                field={@form[:caption]}
                label="Caption (Optional)"
                placeholder="Optional visible caption below the image"
              />
            </div>
            <div>
              <label class="gf-label">Display Size</label>
              <div class="mt-2 space-y-2">
                <div class="flex flex-wrap gap-2">
                  <.size_radio form={@form} value="small" label="Small (200px)" />
                  <.size_radio form={@form} value="medium" label="Medium (400px)" />
                  <.size_radio form={@form} value="large" label="Large (600px)" />
                  <.size_radio form={@form} value="full" label="Full Width" />
                  <.size_radio form={@form} value="custom" label="Custom" />
                </div>
                <div
                  :if={Phoenix.HTML.Form.input_value(@form, :size_preset) == "custom"}
                  class="flex items-center gap-2"
                >
                  <.input
                    field={@form[:custom_width]}
                    type="number"
                    placeholder="Width in pixels"
                    min="50"
                    max="2000"
                    class="w-32"
                  />
                  <span class="text-sm text-gray-500">pixels</span>
                </div>
              </div>
            </div>
          </.form>
        </div>
        <div class="p-4 border-t border-gray-200 flex justify-end gap-2">
          <button
            type="button"
            phx-click="close_image_insert_modal"
            class="px-4 py-2 text-gray-700 border border-gray-300 rounded-md hover:bg-gray-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            form="image-insert-form"
            class="px-4 py-2 bg-gf-maroon text-white rounded-md hover:bg-gf-maroon/90"
          >
            Insert Image
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Size radio button component
  defp size_radio(assigns) do
    ~H"""
    <label class="inline-flex items-center">
      <input
        type="radio"
        name={@form[:size_preset].name}
        value={@value}
        checked={Phoenix.HTML.Form.input_value(@form, :size_preset) == @value}
        class="mr-2"
      /> {@label}
    </label>
    """
  end

  # Image grid component
  defp image_grid(assigns) do
    ~H"""
    <div>
      <p class="text-sm text-gray-500 mb-4">Click an image to insert it at the cursor position.</p>
      <%= if @images == [] do %>
        <div class="p-8 text-center text-gray-500">
          <.icon name="ph-images" class="h-12 w-12 mx-auto text-gray-300 mb-4" />
          <%= if @filter == "" do %>
            <p>No images found. Upload some images first.</p>
          <% else %>
            <p>No images for this article. Try selecting a different article or "All Articles".</p>
          <% end %>
        </div>
      <% else %>
        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4">
          <div
            :for={image <- @images}
            class="group relative aspect-square bg-gray-100 rounded-lg overflow-hidden border-2 border-transparent hover:border-gf-maroon"
          >
            <img src={image.url} alt={image.name} class="w-full h-full object-cover" loading="lazy" />
            <div class="absolute inset-0 bg-black/0 group-hover:bg-black/40 transition-colors flex items-center justify-center gap-2">
              <button
                type="button"
                phx-click="select_image"
                phx-value-url={image.url}
                phx-value-name={image.name}
                class="opacity-0 group-hover:opacity-100 transition-opacity px-3 py-1.5 bg-gf-maroon text-white text-sm font-medium rounded hover:bg-gf-maroon/80"
              >
                Insert
              </button>
              <button
                type="button"
                phx-click="confirm_delete_image"
                phx-value-url={image.url}
                phx-value-path={image.path}
                phx-value-name={image.name}
                class="opacity-0 group-hover:opacity-100 transition-opacity px-3 py-1.5 bg-red-600 text-white text-sm font-medium rounded hover:bg-red-700"
              >
                Delete
              </button>
            </div>
            <div class="absolute bottom-0 left-0 right-0 bg-black/60 px-2 py-1">
              <p class="text-white text-xs truncate">
                {get_article_title(@article_options, image.article_id) || image.folder}
              </p>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Private helpers

  defp normalize_params(params) do
    tags = params["tags"] || []

    params
    |> Map.put("tags", tags)
    |> Map.put("is_published", params["is_published"] == "true")
  end

  defp render_preview(nil), do: nil
  defp render_preview(""), do: nil

  defp render_preview(content) do
    {:ok, html} = Markdown.render(content)
    html
  end

  defp do_insert_image(socket, params, alt_text) do
    caption = String.trim(params["caption"] || "")
    width = parse_image_width(params["size_preset"] || "medium", params["custom_width"])
    html = generate_image_html(socket.assigns.selected_image.url, alt_text, caption, width)

    socket
    |> push_event("insert_image_markdown", %{markdown: html})
    |> assign(:show_image_insert_modal, false)
    |> assign(:show_image_browser, false)
    |> assign(:selected_image, nil)
    |> assign(:image_insert_form, nil)
    |> mark_dirty()
    |> put_flash(:info, "Image inserted at cursor!")
  end

  defp parse_image_width("small", _), do: 200
  defp parse_image_width("medium", _), do: 400
  defp parse_image_width("large", _), do: 600
  defp parse_image_width("full", _), do: nil
  defp parse_image_width("custom", custom_width), do: parse_custom_width(custom_width)

  defp parse_custom_width(nil), do: 400
  defp parse_custom_width(""), do: 400

  defp parse_custom_width(value) when is_binary(value) do
    case Integer.parse(value) do
      {width, _} when width >= 50 and width <= 2000 -> width
      _ -> 400
    end
  end

  defp parse_custom_width(_), do: 400

  defp generate_image_html(url, alt_text, caption, width) do
    escaped_alt = Phoenix.HTML.html_escape(alt_text) |> Phoenix.HTML.safe_to_string()
    width_attr = if width, do: " width=\"#{width}\"", else: ""

    if caption == "" do
      "<img src=\"#{url}\" alt=\"#{escaped_alt}\"#{width_attr}>"
    else
      escaped_caption = Phoenix.HTML.html_escape(caption) |> Phoenix.HTML.safe_to_string()

      """
      <figure>
        <img src="#{url}" alt="#{escaped_alt}"#{width_attr}>
        <figcaption>#{escaped_caption}</figcaption>
      </figure>
      """
      |> String.trim()
    end
  end

  defp format_s3_error({:http_error, 403, %{body: body}}) when is_binary(body) do
    cond do
      String.contains?(body, "AccessDenied") and String.contains?(body, "DeleteObject") ->
        "Permission denied: The S3 user doesn't have delete permissions. Contact an administrator."

      String.contains?(body, "AccessDenied") ->
        "Permission denied: Access to S3 was denied."

      true ->
        "Failed to delete image (403 Forbidden)"
    end
  end

  defp format_s3_error({:http_error, status, _}) do
    "Failed to delete image (HTTP #{status})"
  end

  defp format_s3_error(reason) do
    "Failed to delete image: #{inspect(reason)}"
  end

  defp get_article_title(_article_options, nil), do: nil

  defp get_article_title(article_options, article_id) do
    case Enum.find(article_options, fn {id, _title} -> id == article_id end) do
      {_, title} -> title
      nil -> nil
    end
  end
end
