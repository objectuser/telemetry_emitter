defmodule TelemetryEmitter.Emitter do
  @moduledoc """
  Emit metrics declared with `Telemetry.Metrics`.

  Metric names are represented at strings separated by `.` or lists of atoms.
  Each name must have at least two segments, the last segment being the
  measurement.

  All functions have the metric as the first argument. There is also an optional
  `metadata` argument that accepts a map of metric metadata, including tag
  values.

  ### Examples

  Increment a counter:

  ```elixir
  Emitter.increment("request.count")
  ```

  Or:

  ```elixir
  Emitter.increment([:request, :count])
  ```

  Measure the time of a function call:

  ```elixir
  Emitter.measure("request.stop.duration", %{operation: "op1"}, fn ->
    {Service.operation(...), %{}}
  end)
  ```
  """

  @doc """
  Increment the value of the counter metric. The last segment of the metric is
  the measurement.

  Define the metric using `Telemetry.Metrics.counter/2`.

  ```elixir
  Telemetry.Metrics.counter("request.count")
  ```

  Then emit the metric using the same name:

  ```
  Emitter.increment("request.count")
  ```

  The metric will be emitted as `request` with the measurement `%{count: 1}`.

  > #### Note {: .tip}
  >
  > If the metric is delcared as a counter, the measurement value will always be
  > 1.

  Define the metric as a `sum` to increment the value by more than 1:

  ```elixir
  Telemetry.Metrics.sum("request.count")
  ```

  Then emit the metric using the same name:

  ```
  Emitter.increment("request.count", 99)
  ```

  The metric will be emitted as `request` with the measurement `%{count: 99}`.
  """
  @spec increment(
          counter :: String.t() | [atom()],
          count :: integer(),
          metadata :: %{String.t() => String.t()} | %{atom() => String.t()}
        ) :: :ok
  def increment(counter, count \\ 1, metadata \\ %{})

  def increment(counter, count, metadata) when is_binary(counter) and is_integer(count) do
    counter
    |> to_list_of_atoms()
    |> increment(count, metadata)
  end

  def increment(counter, count, metadata) when is_list(counter) and is_integer(count) do
    counter
    |> split()
    |> then(fn {metric, measurement} ->
      :telemetry.execute(metric, %{measurement => count}, metadata)
    end)
  end

  @doc """
  Emit the current value of the gauge as a number.

  Define the metric using `Telemetry.Metrics.last_value/2`.

  ```elixir
  Telemetry.Metrics.last_value("memory_usage.ratio")
  ```

  Then emit the metric using the same name:

  ```
  Emitter.gauge("memory_usage.ratio", 0.88)
  ```

  The metric will be emitted as `memory_usage` with the measurement, `%{ratio:
  0.88}`.
  """
  @spec gauge(
          metric :: String.t() | [atom()],
          value :: number(),
          metadata :: %{String.t() => String.t()} | %{atom() => String.t()}
        ) :: :ok
  def gauge(metric, value, metadata \\ %{})

  def gauge(metric, value, metadata) when is_binary(metric) and is_number(value) do
    metric
    |> to_list_of_atoms()
    |> gauge(value, metadata)
  end

  def gauge(metric, value, metadata) when is_list(metric) and is_number(value) do
    metric
    |> split()
    |> then(fn {metric, measurement} ->
      :telemetry.execute(metric, %{measurement => value}, metadata)
    end)
  end

  @doc """
  Measure the duration of the given function.

  The metric name may be the same as the `.stop` metric: `prefix.stop.duration`
  where `prefix` is any aribitrary metric name and the suffix `.stop.duration`
  is required. The metric is reported as `prefix.stop` with a measurement of
  `:duration`.

  Alternatively, the `.stop.duration` portion may be omitted for convenience. In
  this case the metric argument must match the prefix of the declared metric.

  The given function must return a tuple, `{return_value, stop_metadata}`.

  The `start_metadata` parameter is emitted for the `.start` event. The
  `stop_metadata` is emitted for the `.stop` event.

  The `return_value` will be the value returned by this function.

  Define the metric using `Telemetry.Metrics.summary/2`.

  ## Examples

  Declaring the metric using `Telemetry.Metrics.summary/2`:

  ```elixir
  Telemetry.Metrics.summary("my.external.service.call.start.system_time", tags: [:operation], unit: {:native, :millisecond})
  Telemetry.Metrics.summary("my.external.service.call.stop.duration", tags: [:operation], unit: {:native, :millisecond})
  Telemetry.Metrics.summary("my.external.service.call.exception.duration", tags: [:operation], unit: {:native, :millisecond})
  ```

  Emitting the metric using `TelemetryEmitter.Emitter.measure/3`:

  ```elixir
  Emitter.measure("my.external.service.call", %{operation: :record}, fn ->
    {MyExternalService.call(...), %{}}
  end)
  ```

  Note the use of the base metric name in the first argument to `measure/3`. You
  may also use the full `.stop` name, `my.external.service.call.stop.duration`.
  Do not use the metric `.start.system_time` suffix in the first argument.

  If the metric with both the `.start.system_time` and `.stop.duration` suffixes
  are declared, both will be emitted:
  1. The `my.external.service.call.start` metric will be emitted with a
     `system_time` measurement of the start time of the call.
  1. The `my.external.service.call.stop` metric will be emitted with a
     `duration` measurement of the duration of calling the function parameter.
  1. The `my.external.service.call.exception` metric will be emitted if an
     exception is raised. It will have a `duration` measurement of the duration
     of calling the function parameter.

  This function delegates to `:telemetry.span/3`, so see the documentation for
  that function for additional information.
  """
  @spec measure(
          metric :: String.t() | [atom()],
          start_metadata :: %{String.t() => String.t()} | %{atom() => String.t()},
          function :: function()
        ) :: :ok | any()
  def measure(metric, start_metadata \\ %{}, function)

  def measure(metric, start_metadata, function) when is_binary(metric) do
    metric
    |> to_list_of_atoms()
    |> measure(start_metadata, function)
  end

  def measure(metric, start_metadata, function) when is_list(metric) do
    metric
    |> stop_duration_split()
    |> then(fn
      {prefix, [:stop, :duration]} ->
        :telemetry.span(prefix, start_metadata, function)

      prefix ->
        :telemetry.span(prefix, start_metadata, function)
    end)
  end

  @doc """
  Emit a metric with explicit measurements.

  This works with any of the declarations from `Telemetry.Metrics`. In this
  case, measurements are provided by the `measurements` argument and the
  entirety of `metric` is used as the name of the emitted Telemetry event.

  This is largely an alias for `:telemetry.execute/3`.

  ## Examples

  ```
  counter("service.request.count"),
  summary("service.request.duration", unit: {:native, :millisecond}),
  ```

  ```
  Emitter.emit("service.request", %{count: 1, duration: 5})
  ```

  The metric `service.request` will be emitted with both the `count` and
  `duration` measurements.
  """
  @spec emit(metric :: String.t() | [atom()], measurements :: map(), metadata :: map()) :: :ok

  def emit(metric, measurements, metadata \\ %{})

  def emit(metric, %{} = measurements, metadata) when is_binary(metric) do
    metric
    |> to_list_of_atoms()
    |> :telemetry.execute(measurements, metadata)
  end

  def emit(metric, %{} = measurements, metadata) when is_list(metric) do
    :telemetry.execute(metric, measurements, metadata)
  end

  @spec split([atom()]) :: {[atom()], atom()}
  defp split(metric) do
    metric
    |> Enum.split(-1)
    |> then(fn
      {[], [_measurement]} ->
        raise """
        Metric names must have at least one segment separating the metric name from the measurement:
        \t`metric_name.measurement` or `metric.name.measurement`, etc.

        \t#{metric} has no segments.
        """

      {metric, [measurement]} ->
        {metric, measurement}
    end)
  end

  @spec stop_duration_split([atom()]) :: {[atom()], [atom()]} | [atom()]
  defp stop_duration_split(metric) do
    metric
    |> Enum.split(-2)
    |> then(fn
      {prefix, [:stop, :duration]} ->
        {prefix, [:stop, :duration]}

      _ ->
        metric
    end)
  end

  @spec to_list_of_atoms(metric :: String.t()) :: [atom()]
  defp to_list_of_atoms(metric) do
    metric
    |> String.split(".")
    |> Enum.map(&String.to_atom/1)
  end
end
