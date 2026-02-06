defmodule Gallformers.Images.AuditCache do
  @moduledoc """
  GenServer that caches orphan image scan results.

  Orphan detection requires listing all S3 objects and cross-referencing
  with the database, which is expensive. This cache stores the results
  with a configurable TTL (default 1 hour).

  ## Usage

      # Get orphans for a specific page
      {orphans, total, stale?} = AuditCache.get_orphans(page: 1, per_page: 50)

      # Get just the count
      {count, stale?} = AuditCache.get_count()

      # Get cache status
      %{count: n, last_scanned: dt, stale?: bool, scanning?: bool} = AuditCache.status()

      # Manually trigger a refresh
      :ok = AuditCache.refresh()
  """
  use GenServer

  require Logger

  alias Gallformers.Images.Audit

  # Default TTL of 1 hour
  @default_ttl_ms :timer.hours(1)

  # State structure
  defstruct orphan_paths: [],
            orphan_count: 0,
            last_scanned: nil,
            scanning?: false,
            scan_error: nil

  # =============================================================================
  # Client API
  # =============================================================================

  @doc """
  Starts the AuditCache GenServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets a page of orphan paths.

  Returns `{orphan_list, total_count, stale?}`.

  If the cache is empty or stale, triggers a background refresh and returns
  current (possibly empty/stale) data immediately.

  Options:
  - :page - page number (default 1)
  - :per_page - items per page (default 50)
  """
  @spec get_orphans(keyword()) :: {[map()], integer(), boolean()}
  def get_orphans(opts \\ []) do
    GenServer.call(__MODULE__, {:get_orphans, opts})
  end

  @doc """
  Gets the total orphan count.

  Returns `{count, stale?}`.
  """
  @spec get_count() :: {integer(), boolean()}
  def get_count do
    GenServer.call(__MODULE__, :get_count)
  end

  @doc """
  Gets the current cache status.

  Returns a map with:
  - :count - number of orphans
  - :last_scanned - DateTime of last successful scan (or nil)
  - :stale? - whether the cache is past its TTL
  - :scanning? - whether a scan is currently in progress
  - :error - last scan error (or nil)
  """
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Triggers a cache refresh.

  The scan runs asynchronously in the background.
  Returns :ok immediately.
  """
  @spec refresh() :: :ok
  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  # =============================================================================
  # GenServer Callbacks
  # =============================================================================

  @impl true
  def init(opts) do
    ttl = Keyword.get(opts, :ttl_ms, @default_ttl_ms)
    state = %__MODULE__{}

    # Store TTL in process dictionary for easy access
    Process.put(:ttl_ms, ttl)

    {:ok, state}
  end

  @impl true
  def handle_call({:get_orphans, opts}, _from, state) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)

    # Check if we need to refresh
    stale? = stale?(state)

    if (stale? or state.orphan_paths == []) and not state.scanning? do
      trigger_async_scan(self())
    end

    # Paginate the cached results
    offset = (page - 1) * per_page

    orphans =
      state.orphan_paths
      |> Enum.drop(offset)
      |> Enum.take(per_page)

    {:reply, {orphans, state.orphan_count, stale?}, state}
  end

  @impl true
  def handle_call(:get_count, _from, state) do
    stale? = stale?(state)

    if (stale? or state.last_scanned == nil) and not state.scanning? do
      trigger_async_scan(self())
    end

    {:reply, {state.orphan_count, stale?}, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      count: state.orphan_count,
      last_scanned: state.last_scanned,
      stale?: stale?(state),
      scanning?: state.scanning?,
      error: state.scan_error
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    if state.scanning? do
      {:noreply, state}
    else
      trigger_async_scan(self())
      {:noreply, %{state | scanning?: true, scan_error: nil}}
    end
  end

  @impl true
  def handle_info({:scan_started}, state) do
    {:noreply, %{state | scanning?: true, scan_error: nil}}
  end

  @impl true
  def handle_info({:scan_complete, orphans}, state) do
    Logger.info("Image audit cache scan complete: found #{length(orphans)} orphans")

    new_state = %{
      state
      | orphan_paths: orphans,
        orphan_count: length(orphans),
        last_scanned: DateTime.utc_now(),
        scanning?: false,
        scan_error: nil
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:scan_error, reason}, state) do
    Logger.error("Image audit cache scan failed: #{inspect(reason)}")

    {:noreply, %{state | scanning?: false, scan_error: reason}}
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp stale?(%{last_scanned: nil}), do: true

  defp stale?(%{last_scanned: last_scanned}) do
    ttl_ms = Process.get(:ttl_ms, @default_ttl_ms)
    age_ms = DateTime.diff(DateTime.utc_now(), last_scanned, :millisecond)
    age_ms > ttl_ms
  end

  defp trigger_async_scan(server_pid) do
    Gallformers.Async.run(fn ->
      send(server_pid, {:scan_started})

      case do_scan() do
        {:ok, orphans} ->
          send(server_pid, {:scan_complete, orphans})

        {:error, reason} ->
          send(server_pid, {:scan_error, reason})
      end
    end)
  end

  defp do_scan do
    Logger.info("Starting image audit cache scan...")

    case Audit.list_all_s3_gall_paths() do
      {:ok, s3_objects} ->
        Logger.info("Listed #{length(s3_objects)} S3 gall images, finding orphans...")
        orphans = Audit.find_orphan_paths(s3_objects)
        {:ok, orphans}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
