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

  import GallformersWeb.Admin.FormComponents, only: [form_actions: 1]

  require Logger

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Articles
  alias Gallformers.Articles.Article
  alias Gallformers.Markdown
  alias Gallformers.Storage.Images, as: ImageStorage

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
      |> assign(:show_delete_modal, false)
      |> assign(:delete_confirmation, "")
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
    |> assign(:page_title, "New article")
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
    {:noreply,
     socket
     |> assign(:show_delete_modal, true)
     |> assign(:delete_confirmation, "")}
  end

  @impl true
  def handle_event("update_delete_confirmation", %{"value" => value}, socket) do
    {:noreply, assign(socket, :delete_confirmation, value)}
  end

  @impl true
  def handle_event("confirm_delete", %{"confirmation" => confirmation}, socket) do
    selected_article = socket.assigns.article

    case selected_article && Articles.get_article(selected_article.id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:info, "Article already deleted")
         |> push_navigate(to: ~p"/admin/articles")}

      article when confirmation != article.title ->
        {:noreply,
         put_flash(socket, :error, "Title does not match. Type the exact article title.")}

      article ->
        case Articles.delete_article(article) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Article deleted successfully")
             |> push_navigate(to: ~p"/admin/articles")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete article")}
        end
    end
  end

  @impl true
  def handle_event("cancel_delete", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_modal, false)
     |> assign(:delete_confirmation, "")}
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
        {ImageStorage.list_article_images_for_article(article.id), article.id}
      else
        {ImageStorage.list_article_images(), ""}
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
    images = ImageStorage.list_article_images()

    {:noreply,
     socket
     |> assign(:article_images, images)
     |> assign(:image_browser_filter, "")}
  end

  @impl true
  def handle_event("filter_images_by_article", %{"article_id" => article_id}, socket) do
    article_id = String.to_integer(article_id)
    images = ImageStorage.list_article_images_for_article(article_id)

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

    case ImageStorage.delete_article_image(image.path) do
      :ok ->
        # Refresh the image list
        images =
          case socket.assigns.image_browser_filter do
            "" -> ImageStorage.list_article_images()
            article_id -> ImageStorage.list_article_images_for_article(article_id)
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
      path = ImageStorage.generate_article_path(article.id, ext)

      case ImageStorage.presigned_upload_url(path, type) do
        {:ok, url} ->
          image_url = ImageStorage.article_image_url(path)

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

  # Content image manager notifications (component manages its own state)
  @impl true
  def handle_info({:image_uploaded, _image}, socket), do: {:noreply, socket}
  def handle_info({:image_deleted, _id}, socket), do: {:noreply, socket}
  def handle_info({:images_reordered, _order}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:crumb navigate={~p"/admin/articles"}>Articles</:crumb>
          <:title>{if @mode == :edit, do: @article.title, else: "New article"}</:title>
          <:chip :if={@mode == :edit} variant={if @article.is_published, do: :ok, else: :warn}>
            {if @article.is_published, do: "Published", else: "Draft"}
          </:chip>
          <:meta :if={@mode == :edit} label="Updated">
            {format_date(@article.updated_at, :short)}
          </:meta>
          <:description>
            Written in Markdown. Glossary terms are linked automatically.
          </:description>
          <:action :if={@mode == :edit}>
            <.button
              href={~p"/articles/#{@article.slug}"}
              target="_blank"
              variant="ghost"
              size="sm"
              icon="ph-arrow-square-out"
            >
              {if @article.is_published, do: "View on site", else: "Preview on site"}
            </.button>
          </:action>
        </.page_header>

        <.image_browser
          :if={@show_image_browser}
          images={@article_images}
          article_options={@article_options}
          filter={@image_browser_filter}
        />

        <div :if={!@show_image_browser} class="gf-with-rail">
          <div class="flex max-w-form min-w-0 flex-col gap-block">
            <div class="flex items-center gap-2">
              <.button
                :if={@active_tab == :edit}
                variant="ghost"
                size="sm"
                icon="ph-eye"
                phx-click="switch_tab"
                phx-value-tab="preview"
              >
                Preview
              </.button>
              <.button
                :if={@active_tab == :preview}
                variant="ghost"
                size="sm"
                icon="ph-pencil-simple"
                phx-click="switch_tab"
                phx-value-tab="edit"
              >
                Back to editing
              </.button>
            </div>

            <.form
              :if={@active_tab == :edit}
              for={@form}
              id="article-form"
              phx-submit="save"
              phx-change="validate"
              class="flex flex-col gap-block"
            >
              <.input field={@form[:title]} schema={Article} label="Title" />
              <div>
                <.input field={@form[:slug]} label="Slug" placeholder="made from the title if blank" />
                <p class="gf-hint">The article's address: /articles/<em>slug</em>.</p>
              </div>
              <.input field={@form[:author]} schema={Article} label="Author" />
              <div>
                <.input
                  type="textarea"
                  field={@form[:description]}
                  label="Description"
                  placeholder="A sentence or two"
                  rows={2}
                />
                <p class="gf-hint">Optional. Shown in the Articles list and to search engines.</p>
              </div>
              <div>
                <.input
                  type="textarea"
                  field={@form[:content]}
                  schema={Article}
                  label="Content (Markdown)"
                  rows={20}
                  class="gf-textarea font-mono text-meta"
                />
                <div class="mt-1 flex flex-wrap items-center justify-between gap-2">
                  <p class="gf-hint">Glossary terms are linked automatically.</p>
                  <div :if={@article.id} class="flex items-center gap-2">
                    <div
                      id="article-image-upload"
                      phx-hook="ArticleImageUpload"
                      phx-update="ignore"
                      data-content-textarea={@form[:content].id}
                      class="flex items-center gap-2"
                    >
                      <.button type="button" variant="secondary" size="sm" data-upload-trigger>
                        Upload image
                      </.button>
                      <input
                        data-file-input
                        type="file"
                        accept="image/jpeg,image/png"
                        class="hidden"
                      />
                      <span data-status class="text-meta"></span>
                    </div>
                    <.button
                      type="button"
                      variant="secondary"
                      size="sm"
                      phx-click="open_image_browser"
                    >
                      Browse images
                    </.button>
                  </div>
                  <p :if={!@article.id} class="gf-hint">Save the article first to add images.</p>
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
                <p class="gf-hint">Choose a tag, or type a new one and press Enter.</p>
              </div>
              <.input type="checkbox" field={@form[:is_published]} label="Published" />

              <div class="flex justify-end border-t border-line pt-block">
                <.form_actions form_dirty={@form_dirty} mode={@mode} create_label="Create article" />
              </div>
            </.form>

            <div
              :if={@active_tab == :preview}
              class="rounded-panel border border-line bg-surface p-panel"
            >
              <.prose :if={@preview_content} size={:sm}>{Phoenix.HTML.raw(@preview_content)}</.prose>
              <p :if={!@preview_content} class="text-ui italic text-muted">
                Nothing to preview yet: write some content first.
              </p>
            </div>

            <.section :if={@mode == :edit} id="content-images" title="Content images">
              <.live_component
                module={GallformersWeb.Admin.ContentImageManager}
                id="article-content-images"
                owner_type={:article}
                owner_id={@article.id}
                current_user={@current_user}
              />
            </.section>
          </div>

          <.rail :if={@mode == :edit} width={:narrow}>
            <.panel id="danger" variant={:danger} title="Delete">
              <p class="mb-3 text-ui text-ink-2">
                Deletes the article and every image it owns. You'll be asked to type its title.
              </p>
              <.button variant="danger" phx-click="delete">Delete…</.button>
            </.panel>
          </.rail>
        </div>

        <.image_insert_dialog
          :if={@show_image_insert_modal && @selected_image}
          image={@selected_image}
          form={@image_insert_form}
        />
        <.image_delete_dialog
          :if={@image_to_delete}
          image={@image_to_delete}
          references={@image_references}
        />

        <.discard_confirm_modal show={@show_discard_confirm} />

        <.dangerous_delete_modal
          :if={@article}
          show={@show_delete_modal}
          item_type="article"
          item_name={@article.title}
          consequences={[
            "The article content, publication state, and tags will be permanently deleted.",
            "All images owned by this article will be deleted from storage."
          ]}
          confirmation_value={@delete_confirmation}
        />
      </div>
    </Layouts.admin>
    """
  end

  # The image browser: replaces the form while open. Choosing an image
  # opens the insert dialog; Delete opens the delete-image dialog.
  attr :images, :list, required: true
  attr :article_options, :list, required: true
  attr :filter, :any, required: true

  defp image_browser(assigns) do
    ~H"""
    <section id="image-browser" class="flex flex-col gap-block">
      <div class="flex flex-wrap items-end gap-3">
        <.button
          variant="ghost"
          size="sm"
          icon="ph-arrow-left"
          phx-click="close_image_browser"
        >
          Back to the article
        </.button>
        <h2 class="text-section">Article images</h2>
        <.filter_select
          id="image-article-filter"
          name="article_id"
          label="Article"
          prompt="Every article"
          value={@filter}
          options={Enum.map(@article_options, fn {id, title} -> {title, id} end)}
          class="ml-auto w-64"
          phx-change="filter_images_by_article"
        />
      </div>

      <p :if={@images == []} data-part="empty" class="text-ui text-muted">
        {if @filter == "",
          do: "No images yet. Upload one from the article's Content field.",
          else: "No images for this article. Choose another article, or every article."}
      </p>

      <div :if={@images != []} class="flex flex-col gap-2">
        <p class="text-meta text-muted">Choose an image to insert it at the cursor.</p>
        <ul class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
          <li
            :for={image <- @images}
            class="flex flex-col overflow-hidden rounded-panel border border-line bg-surface"
          >
            <img
              src={image.url}
              alt={image.name}
              class="aspect-square w-full bg-surface-2 object-cover"
              loading="lazy"
            />
            <div class="flex flex-col gap-1.5 p-2">
              <span class="truncate text-meta text-muted">
                {get_article_title(@article_options, image.article_id) || image.folder}
              </span>
              <div class="flex gap-1.5">
                <.button
                  variant="primary"
                  size="sm"
                  phx-click="select_image"
                  phx-value-url={image.url}
                  phx-value-name={image.name}
                >
                  Insert
                </.button>
                <.button
                  variant="ghost"
                  size="sm"
                  phx-click="confirm_delete_image"
                  phx-value-url={image.url}
                  phx-value-path={image.path}
                  phx-value-name={image.name}
                >
                  Delete…
                </.button>
              </div>
            </div>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  attr :image, :map, required: true
  attr :form, :any, required: true

  defp image_insert_dialog(assigns) do
    ~H"""
    <.dialog
      id="insert-image"
      title="Insert image"
      show
      on_cancel={JS.push("close_image_insert_modal")}
    >
      <div class="flex flex-col gap-block">
        <img src={@image.url} alt="" class="max-h-48 self-center rounded-ctl object-contain" />
        <.form
          for={@form}
          id="image-insert-form"
          phx-submit="insert_image"
          phx-change="validate_image_insert"
          class="flex flex-col gap-block"
        >
          <div>
            <.input
              field={@form[:alt_text]}
              label="Alt text"
              placeholder="What the image shows"
              required
            />
            <p class="gf-hint">Read aloud by screen readers in place of the image.</p>
          </div>
          <.input
            field={@form[:caption]}
            label="Caption (optional)"
            placeholder="Shown under the image"
          />
          <fieldset class="flex flex-col gap-2">
            <legend class="gf-label">Size</legend>
            <div class="flex flex-wrap gap-x-4 gap-y-2">
              <.size_radio form={@form} value="small" label="Small (200px)" />
              <.size_radio form={@form} value="medium" label="Medium (400px)" />
              <.size_radio form={@form} value="large" label="Large (600px)" />
              <.size_radio form={@form} value="full" label="Full width" />
              <.size_radio form={@form} value="custom" label="Custom" />
            </div>
            <div
              :if={Phoenix.HTML.Form.input_value(@form, :size_preset) == "custom"}
              class="flex items-center gap-2"
            >
              <.input
                field={@form[:custom_width]}
                type="number"
                placeholder="Width"
                min="50"
                max="2000"
                class="gf-input w-32"
              />
              <span class="text-meta text-muted">pixels</span>
            </div>
          </fieldset>
        </.form>
      </div>
      <:actions>
        <.button variant="ghost" phx-click="close_image_insert_modal">Cancel</.button>
        <.button type="submit" form="image-insert-form" variant="primary">Insert image</.button>
      </:actions>
    </.dialog>
    """
  end

  attr :image, :map, required: true
  attr :references, :list, required: true

  defp image_delete_dialog(assigns) do
    ~H"""
    <.dialog
      id="delete-image"
      title="Delete this image?"
      size={:sm}
      show
      on_cancel={JS.push("cancel_delete_image")}
    >
      <div class="flex flex-col gap-block">
        <img src={@image.url} alt="" class="max-h-32 self-center rounded-ctl object-contain" />
        <p :if={@references == []} class="text-ui text-ink">
          No article uses it. This can't be undone.
        </p>
        <.notice
          :if={@references != []}
          kind={:warn}
          title={"Used in #{length(@references)} #{if length(@references) == 1, do: "article", else: "articles"}"}
        >
          <ul class="list-disc pl-5">
            <li :for={{_id, title} <- @references}>{title}</li>
          </ul>
          Deleting it breaks the image in each.
        </.notice>
      </div>
      <:actions>
        <.button variant="ghost" phx-click="cancel_delete_image">Keep it</.button>
        <.button variant="danger" phx-click="delete_image">
          {if @references == [], do: "Delete", else: "Delete anyway"}
        </.button>
      </:actions>
    </.dialog>
    """
  end

  attr :form, :any, required: true
  attr :value, :string, required: true
  attr :label, :string, required: true

  defp size_radio(assigns) do
    ~H"""
    <label class="inline-flex items-center gap-1.5 text-ui text-ink">
      <input
        type="radio"
        name={@form[:size_preset].name}
        value={@value}
        checked={Phoenix.HTML.Form.input_value(@form, :size_preset) == @value}
      />
      {@label}
    </label>
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
