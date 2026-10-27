defmodule GallformersWeb.Admin.QueueLive.Package do
  @moduledoc """
  One import package under review (`/admin/queue/packages/:id`, matter
  a856 Task 3): the package (status, submitter, Source, validation
  problems); its queue items, each with its decision controls
  (`GallformersWeb.Admin.QueueLive.ItemDecision`); and its batches — type,
  mode and status, their queue items, their statements with how each
  resolved (to what, among which candidates, and once applied its delta),
  and their unmapped entries.

  The package is approved (`Gallformers.Import.approve_package/2`; what
  holds it is shown), denied, or one of its batches denied, with a reason
  (`Gallformers.Import.deny_package/3`, `deny_batch/3`), or resolved again
  (`Gallformers.Import.resolve_package/2`, after a name was added to the
  tree, say). Every write is the signed-in admin's (`:actor`).
  """
  use GallformersWeb, :live_view

  import GallformersWeb.Admin.QueueLive.Components

  alias Gallformers.Import
  alias Gallformers.Import.Batch
  alias Gallformers.Import.Package
  alias Gallformers.Sources
  alias GallformersWeb.Admin.QueueLive.ItemDecision

  @resolvable [:validated, :resolving, :awaiting_review]
  @deniable [:received, :invalid, :validated, :resolving, :awaiting_review]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(package_id: id, held: nil, deny_target: nil, deny_form: deny_form())
     |> load()}
  end

  @impl true
  def handle_event("approve", _params, socket) do
    case Import.approve_package(socket.assigns.actor, socket.assigns.package) do
      {:ok, _package} ->
        {:noreply,
         socket
         |> assign(held: nil)
         |> put_flash(
           :info,
           "The package was approved; its batches are applied by the import worker."
         )
         |> load()}

      {:error, {:open_items, _items} = held} ->
        {:noreply, socket |> assign(held: held) |> load()}

      {:error, {:blocked, _batches} = held} ->
        {:noreply, socket |> assign(held: held) |> load()}

      {:error, :not_approvable} ->
        {:noreply,
         socket |> put_flash(:error, "Only a package awaiting review can be approved.") |> load()}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "The package could not be approved: #{inspect(reason)}")}
    end
  end

  def handle_event("resolve", _params, socket) do
    case Import.resolve_package(socket.assigns.actor, socket.assigns.package) do
      {:ok, _package} ->
        {:noreply,
         socket
         |> assign(held: nil)
         |> put_flash(:info, "The package was resolved again.")
         |> load()}

      {:error, :not_resolvable} ->
        {:noreply, put_flash(socket, :error, "This package can no longer be resolved.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "The package could not be resolved: #{inspect(reason)}")}
    end
  end

  def handle_event("open_deny", %{"batch" => batch_id}, socket) do
    batch = Enum.find(socket.assigns.batches, &(Integer.to_string(&1.id) == batch_id))
    {:noreply, assign(socket, deny_target: batch && {:batch, batch}, deny_form: deny_form())}
  end

  def handle_event("open_deny", _params, socket),
    do: {:noreply, assign(socket, deny_target: :package, deny_form: deny_form())}

  def handle_event("cancel_deny", _params, socket),
    do: {:noreply, assign(socket, deny_target: nil)}

  def handle_event("deny", %{"deny" => %{"reason" => reason}}, socket) do
    %{actor: actor, package: package, deny_target: target} = socket.assigns

    result =
      case target do
        :package -> Import.deny_package(actor, package, reason)
        {:batch, batch} -> Import.deny_batch(actor, batch, reason)
        nil -> {:error, :not_deniable}
      end

    case result do
      {:ok, _denied} ->
        {:noreply,
         socket
         |> assign(deny_target: nil, held: nil)
         |> put_flash(:info, denied_message(target))
         |> load()}

      {:error, %Ecto.Changeset{errors: errors}} ->
        reason_errors = for {:denied_reason, error} <- errors, do: {:reason, error}
        {:noreply, assign(socket, deny_form: deny_form(reason, reason_errors))}

      {:error, :not_deniable} ->
        {:noreply,
         socket
         |> assign(deny_target: nil)
         |> put_flash(:error, "This can no longer be denied.")
         |> load()}
    end
  end

  @impl true
  def handle_info({ItemDecision, {:decided, _item}}, socket) do
    {:noreply, socket |> put_flash(:info, "Decision recorded.") |> load()}
  end

  defp denied_message(:package), do: "The package was denied."
  defp denied_message({:batch, batch}), do: "#{batch.file} was denied."

  defp deny_form(reason \\ "", errors \\ []),
    do: to_form(%{"reason" => reason}, as: :deny, errors: errors)

  defp load(socket) do
    package = Import.get_package!(socket.assigns.package_id)
    batches = Import.list_batches(package)
    statements = Map.new(batches, &{&1.id, Import.list_statements(&1)})
    items = Import.list_queue_items(package, status: :all)

    assign(socket,
      package: package,
      page_title: "Package #{package.key}",
      source: package.source_id && Sources.get_source(package.source_id),
      batches: batches,
      statements: statements,
      unmapped: Map.new(batches, &{&1.id, Import.list_unmapped(&1)}),
      items: Enum.group_by(items, & &1.batch_id),
      names: ItemDecision.names(items, statements |> Map.values() |> List.flatten())
    )
  end

  defp resolvable?(%Package{status: status}), do: status in @resolvable

  defp package_deniable?(%Package{status: status}, batches),
    do: status in @deniable and not Enum.any?(batches, &(&1.status == :applied))

  defp batch_deniable?(%Package{status: status}, %Batch{status: batch_status}),
    do: status in @deniable and batch_status not in [:applied, :denied]

  defp resolution_name(%{kind: :taxon, taxon_id: id}, names) when is_integer(id),
    do: Map.get(names.taxa, id, "taxon #{id}")

  defp resolution_name(%{kind: :gall, gall_id: id}, names) when is_integer(id),
    do: Map.get(names.galls, id, "Gall #{id}")

  defp resolution_name(%{fact_id: id}, _names) when is_integer(id), do: "Fact #{id}"
  defp resolution_name(_statement, _names), do: nil

  defp candidate_names(%{kind: :taxon, candidate_ids: ids}, names),
    do: Enum.map(ids, &Map.get(names.taxa, &1, "taxon #{&1}"))

  defp candidate_names(%{kind: :gall, candidate_ids: ids}, names),
    do: Enum.map(ids, &Map.get(names.galls, &1, "Gall #{&1}"))

  defp candidate_names(_statement, _names), do: []

  defp humanize(nil), do: nil
  defp humanize(value), do: value |> to_string() |> String.replace("_", " ")

  defp held_item_label(item, batches) do
    where =
      case Enum.find(batches, &(&1.id == item.batch_id)) do
        nil -> ""
        batch -> " (#{batch.file})"
      end

    "#{ItemDecision.kind_label(item.kind)} #{item.statement_ref}#{where}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <Layouts.back_link navigate={~p"/admin/queue"} label="Back to the review queue" />

      <div class="space-y-8">
        <.card id="package-header" title={"Package #{@package.key}"}>
          <:actions>
            <.button
              :if={@package.status == :awaiting_review}
              id="approve-package"
              phx-click="approve"
              variant="primary"
              size="sm"
            >
              Approve
            </.button>
            <.button
              :if={resolvable?(@package)}
              id="resolve-package"
              phx-click="resolve"
              size="sm"
            >
              Resolve again
            </.button>
            <.button
              :if={package_deniable?(@package, @batches)}
              id="deny-package"
              phx-click="open_deny"
              variant="danger"
              size="sm"
            >
              Deny
            </.button>
          </:actions>

          <.list>
            <:item title="Status">
              <.status_badge id="package-status" status={@package.status} />
            </:item>
            <:item :if={@package.denied_reason} title="Denied because">
              {@package.denied_reason}
            </:item>
            <:item title="Submitted by">
              {@package.submitter_name} on {format_date(@package.inserted_at, :short)}
            </:item>
            <:item title="Source">
              <.link
                :if={@source}
                navigate={~p"/source/#{@source.id}"}
                class="text-gf-maroon hover:underline"
              >
                {@source.title}
              </.link>
              <span :if={!@source} class="text-gray-500">Not matched yet</span>
            </:item>
            <:item title="Versions">
              format {@package.format_version || "?"}, vocabulary {@package.vocabulary_version || "?"}
            </:item>
          </.list>

          <div :if={@package.problems != []} class="mt-4">
            <h4 class="font-medium text-gray-700 mb-2">Validation problems</h4>
            <ul class="text-sm space-y-1">
              <li :for={problem <- @package.problems}>
                <.badge variant={if problem["level"] == "error", do: "warning", else: "info"}>
                  {problem["level"]}
                </.badge>
                <span :if={problem["file"]} class="font-mono">{problem["file"]}</span>
                {problem["message"]}
              </li>
            </ul>
          </div>
        </.card>

        <.alert :if={@held} id="approval-held" variant="warning">
          <:title>Approval is held</:title>
          <%= case @held do %>
            <% {:open_items, items} -> %>
              <p>Open items a batch needs must be decided first:</p>
              <ul class="list-disc ml-5">
                <li :for={item <- items}>{held_item_label(item, @batches)}</li>
              </ul>
            <% {:blocked, batches} -> %>
              <p>Batches waiting for their Host names to resolve:</p>
              <ul class="list-disc ml-5">
                <li :for={batch <- batches}>{batch.file}</li>
              </ul>
          <% end %>
        </.alert>

        <section :if={@items[nil]} id="package-items" class="space-y-3">
          <.header>About the package's Source</.header>
          <.live_component
            :for={item <- @items[nil]}
            module={ItemDecision}
            id={"item-decision-#{item.id}"}
            item={item}
            actor={@actor}
            names={@names}
          />
        </section>

        <.card
          :for={batch <- @batches}
          id={"batch-#{batch.id}"}
          title={"#{batch.file} — #{batch.batch_type} batch"}
        >
          <:actions>
            <.button
              :if={batch_deniable?(@package, batch)}
              id={"deny-batch-#{batch.id}"}
              phx-click="open_deny"
              phx-value-batch={batch.id}
              variant="danger"
              size="sm"
            >
              Deny this batch
            </.button>
          </:actions>

          <div class="space-y-6">
            <.list>
              <:item title="Status"><.status_badge status={batch.status} /></:item>
              <:item :if={batch.denied_reason} title="Denied because">{batch.denied_reason}</:item>
              <:item title="Mode">{batch.mode}</:item>
              <:item title="Batch ID"><span class="font-mono">{batch.producer_batch_id}</span></:item>
              <:item :if={batch.applied_at} title="Applied">
                {format_date(batch.applied_at, :short)}
              </:item>
            </.list>

            <div :if={@items[batch.id]} id={"batch-items-#{batch.id}"} class="space-y-3">
              <h4 class="font-medium text-gray-700">Queue items</h4>
              <.live_component
                :for={item <- @items[batch.id]}
                module={ItemDecision}
                id={"item-decision-#{item.id}"}
                item={item}
                actor={@actor}
                names={@names}
              />
            </div>

            <div>
              <h4 class="font-medium text-gray-700 mb-2">Statements</h4>
              <div class="overflow-x-auto">
                <.table
                  id={"statements-#{batch.id}"}
                  rows={@statements[batch.id]}
                  row_id={&"statement-#{&1.id}"}
                  variant="compact"
                >
                  <:col :let={s} label="Ref"><span class="font-mono">{s.ref}</span></:col>
                  <:col :let={s} label="Kind">{s.kind}</:col>
                  <:col :let={s} label="As written">{s.detail["name_as_written"]}</:col>
                  <:col :let={s} label="Resolution">
                    {humanize(s.resolution)}
                    <span :if={s.method} class="text-gray-500">({s.method})</span>
                  </:col>
                  <:col :let={s} label="Resolved to">{resolution_name(s, @names)}</:col>
                  <:col :let={s} label="Candidates">
                    {Enum.join(candidate_names(s, @names), "; ")}
                  </:col>
                  <:col :let={s} label="Flags">{Enum.map_join(s.flags, ", ", &humanize/1)}</:col>
                  <:col :let={s} label="Delta">{humanize(s.delta)}</:col>
                </.table>
                <p :if={@statements[batch.id] == []} class="text-sm text-gray-500">
                  Not resolved yet.
                </p>
              </div>
            </div>

            <div>
              <h4 class="font-medium text-gray-700 mb-2">Unmapped entries</h4>
              <div class="overflow-x-auto">
                <.table id={"unmapped-#{batch.id}"} rows={@unmapped[batch.id]} variant="compact">
                  <:col :let={u} label="Term">{u.term}</:col>
                  <:col :let={u} label="Slot">{u.slot}</:col>
                  <:col :let={u} label="Gall"><span class="font-mono">{u.gall_ref}</span></:col>
                  <:col :let={u} label="Note">{u.note}</:col>
                </.table>
                <p :if={@unmapped[batch.id] == []} class="text-sm text-gray-500">None.</p>
              </div>
            </div>
          </div>
        </.card>
      </div>

      <.modal :if={@deny_target} id="deny-modal" show on_cancel={JS.push("cancel_deny")}>
        <:header>
          {if @deny_target == :package,
            do: "Deny package #{@package.key}",
            else: "Deny #{elem(@deny_target, 1).file}"}
        </:header>
        <:body>
          <.form for={@deny_form} id="deny-form" phx-submit="deny" class="space-y-4">
            <p class="text-sm text-gray-600">
              Nothing of a denied {if @deny_target == :package, do: "package", else: "batch"} is
              applied. The reason is kept with it and in the replay log.
            </p>
            <.input field={@deny_form[:reason]} type="textarea" label="Reason" required />
            <div class="flex justify-end gap-2">
              <.button type="button" phx-click="cancel_deny">Cancel</.button>
              <.button type="submit" variant="danger">Deny</.button>
            </div>
          </.form>
        </:body>
      </.modal>
    </Layouts.admin>
    """
  end
end
