defmodule TelemetryEmitter.CaptureReporter do
  @moduledoc """
  A reporter captures measurements in process state. This is useful for testing
  but nothing else.
  """
  use GenServer

  alias __MODULE__

  require Logger

  @doc """
  Initialize the reporter with a list of metrics. Create `metrics` using
  `Telemetry.Metrics`.

  ```
  {:ok, pid} = TelemetryEmitter.CaptureReporter.start_link(metrics: metrics)
  ```
  """
  def start_link(opts) do
    metrics =
      opts[:metrics] ||
        raise ArgumentError, "the :metrics option is required by #{inspect(__MODULE__)}"

    GenServer.start_link(__MODULE__, metrics, opts)
  end

  @doc """
  Return metrics recorded under the given `metric`.

  ```
  Emitter.increment("service.request.count")

  assert %{measurement: %{count: 1}, tags: %{}, unit: :unit} =
            CaptureReporter.recorded(pid, "service.request")
  ```
  """
  def recorded(pid, metric) do
    GenServer.call(pid, {:recorded, metric})
  end

  @impl GenServer
  @doc false
  def init(metrics) do
    Process.flag(:trap_exit, true)
    groups = Enum.group_by(metrics, & &1.event_name)

    for {event, metrics} <- groups do
      id = {__MODULE__, event, self()}
      :telemetry.attach(id, event, &__MODULE__.handle_event/4, {self(), metrics})
    end

    {:ok, {Map.keys(groups), %{}}}
  end

  @impl GenServer
  @doc false
  def terminate(_, {events, _}) do
    for event <- events do
      :telemetry.detach({__MODULE__, event, self()})
    end

    :ok
  end

  @doc false
  def record(pid, metric, data) do
    GenServer.call(pid, {:record, metric, data})
  end

  @impl GenServer
  @doc false
  def handle_call(
        {:record, metric, %{measurement: %{} = measurement} = data},
        _caller,
        {metrics, recorded}
      ) do
    recorded =
      data
      |> then(fn data ->
        Map.update(recorded, metric, data, fn existing ->
          %{existing | measurement: Map.merge(existing.measurement, measurement)}
        end)
      end)

    {:reply, :ok, {metrics, recorded}}
  end

  def handle_call({:record, metric, data}, _caller, {metrics, recorded}) do
    recorded =
      Map.update(recorded, metric, [data], fn existing ->
        [data | existing]
      end)

    {:reply, :ok, {metrics, recorded}}
  end

  @impl GenServer
  def handle_call({:recorded, metric}, _caller, {metrics, recorded}) do
    {:reply, Map.get(recorded, metric), {metrics, recorded}}
  end

  @doc false
  def handle_event(event, measurements, metadata, {pid, metrics}) do
    event_name = Enum.join(event, ".")

    for metric <- metrics do
      try do
        value = extract_measurement(metric, measurements, metadata)
        tags = extract_tags(metric, metadata)

        cond do
          is_nil(value) ->
            CaptureReporter.record(pid, event_name, :missing)

          not keep?(metric, metadata) ->
            CaptureReporter.record(pid, event_name, :dropped)

          true ->
            CaptureReporter.record(pid, event_name, %{
              metric: metric,
              measurement: value,
              unit: metric.unit,
              tags: tags
            })
        end
      rescue
        e ->
          Logger.error([
            "Could not format metric #{inspect(metric)}\n",
            Exception.format(:error, e, __STACKTRACE__)
          ])

          CaptureReporter.record(self(), event_name, :invalid)
      end
    end

    :ok
  end

  defp keep?(%{keep: nil}, _metadata), do: true
  defp keep?(metric, metadata), do: metric.keep.(metadata)

  defp extract_measurement(metric, measurements, metadata) do
    case metric.measurement do
      fun when is_function(fun, 2) -> fun.(measurements, metadata)
      fun when is_function(fun, 1) -> fun.(measurements)
      key -> %{key => measurements[key]}
    end
  end

  defp extract_tags(metric, metadata) do
    tag_values = metric.tag_values.(metadata)
    Map.take(tag_values, metric.tags)
  end
end
