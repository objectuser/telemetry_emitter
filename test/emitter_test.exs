defmodule TelemetryEmitter.EmitterTest do
  @moduledoc """
  Originally taken from `Telemetry.Metrics` and modified for this project.
  """
  use ExUnit.Case

  import Telemetry.Metrics

  alias TelemetryEmitter.Emitter
  alias TelemetryEmitter.CaptureReporter

  def metadata_measurement(_measurements, metadata) do
    %{size: map_size(metadata)}
  end

  def measurement(%{duration: duration} = _measurement) do
    %{duration: duration}
  end

  def tag_values(%{foo: :bar}) do
    %{bar: :baz}
  end

  def drop(metadata) do
    metadata[:boom] == :pow
  end

  setup do
    metrics = [
      last_value("vm.memory.total", unit: :byte),
      counter("service.request.count"),
      summary("service.request.duration", unit: :millisecond),
      sum("service.message.count"),
      summary("service.request.start.system_time", tags: [:foo, :baz]),
      summary("service.request.stop.duration", tags: [:foo, :baz]),
      summary("http.request.response_time",
        tag_values: &__MODULE__.tag_values/1,
        tags: [:bar],
        drop: &__MODULE__.drop/1
      ),
      sum("telemetry.event.size",
        measurement: &__MODULE__.metadata_measurement/2
      ),
      distribution("phoenix.endpoint.stop.duration",
        measurement: &__MODULE__.measurement/1
      )
    ]

    {:ok, pid} = TelemetryEmitter.CaptureReporter.start_link(metrics: metrics)

    %{capture: pid}
  end

  test "increments counter", %{capture: pid} do
    Emitter.increment("service.request.count")

    assert %{measurement: %{count: 1}, tags: %{}, unit: :unit} =
             CaptureReporter.recorded(pid, "service.request")
  end

  test "increments counter given as list", %{capture: pid} do
    Emitter.increment([:service, :request, :count])

    assert %{measurement: %{count: 1}, tags: %{}, unit: :unit} =
             CaptureReporter.recorded(pid, "service.request")
  end

  test "increments counter with value", %{capture: pid} do
    Emitter.increment("service.request.count", 2)

    assert %{measurement: %{count: 2}, tags: %{}, unit: :unit} =
             CaptureReporter.recorded(pid, "service.request")
  end

  test "increments counter with metadata", %{capture: pid} do
    Emitter.increment("service.request.count", 1, %{one: :two})

    assert %{measurement: %{count: 1}, tags: %{}, unit: :unit} =
             CaptureReporter.recorded(pid, "service.request")
  end

  test "increments counter defined as sum", %{capture: pid} do
    Emitter.increment("service.message.count", 100)

    assert %{measurement: %{count: 100}, tags: %{}, unit: :unit} =
             CaptureReporter.recorded(pid, "service.message")
  end

  test "emits last value of gauge", %{capture: pid} do
    Emitter.gauge("vm.memory.total", 100)

    assert %{measurement: %{total: 100}, tags: %{}, unit: :byte} =
             CaptureReporter.recorded(pid, "vm.memory")
  end

  test "emits last value of gauge given as list", %{capture: pid} do
    Emitter.gauge([:vm, :memory, :total], 100)

    assert %{measurement: %{total: 100}, tags: %{}, unit: :byte} =
             CaptureReporter.recorded(pid, "vm.memory")
  end

  test "requires number for measurement" do
    assert_raise FunctionClauseError, fn ->
      Emitter.gauge("vm.memory.total", :hundred, %{foo: :bar})
    end
  end

  test "measures function duration", %{capture: pid} do
    assert :return ==
             Emitter.measure(
               "service.request.stop.duration",
               %{foo: :bar},
               fn -> {:return, %{baz: :bar}} end
             )

    assert %{measurement: %{system_time: _system_time}, tags: %{foo: :bar}, unit: :unit} =
             CaptureReporter.recorded(pid, "service.request.start")

    assert %{measurement: %{duration: _duration}, tags: %{baz: :bar}, unit: :unit} =
             CaptureReporter.recorded(pid, "service.request.stop")
  end

  test "measures function duration when metric given as list", %{capture: pid} do
    assert :return ==
             Emitter.measure(
               [:service, :request, :stop, :duration],
               %{foo: :bar},
               fn -> {:return, %{baz: :bar}} end
             )

    assert %{measurement: %{system_time: _system_time}, tags: %{foo: :bar}, unit: :unit} =
             CaptureReporter.recorded(pid, "service.request.start")

    assert %{measurement: %{duration: _duration}, tags: %{baz: :bar}, unit: :unit} =
             CaptureReporter.recorded(pid, "service.request.stop")
  end

  test "works the same without .stop.duration", %{capture: pid} do
    assert :return ==
             Emitter.measure(
               "service.request",
               %{foo: :bar},
               fn -> {:return, %{baz: :bar}} end
             )

    assert %{measurement: %{system_time: _duration}, tags: %{foo: :bar}, unit: :unit} =
             CaptureReporter.recorded(pid, "service.request.start")

    assert %{measurement: %{duration: _duration}, tags: %{baz: :bar}, unit: :unit} =
             CaptureReporter.recorded(pid, "service.request.stop")
  end

  test "works with an explicit measurement", %{capture: pid} do
    Emitter.emit("service.request.stop", %{duration: 1000}, %{foo: :bar})

    assert %{measurement: %{duration: _duration}, tags: %{foo: :bar}, unit: :unit} =
             CaptureReporter.recorded(pid, "service.request.stop")
  end

  test "works with an explicit measurement given as list", %{capture: pid} do
    Emitter.emit([:service, :request, :stop], %{duration: 1000}, %{foo: :bar})

    assert %{measurement: %{duration: _duration}, tags: %{foo: :bar}, unit: :unit} =
             CaptureReporter.recorded(pid, "service.request.stop")
  end

  test "filters events", %{capture: pid} do
    Emitter.emit("http.request", %{response_time: 1000}, %{foo: :bar, boom: :pow})

    assert [:dropped] == CaptureReporter.recorded(pid, "http.request")
  end

  test "can use metadata in the event measurement calculation", %{capture: pid} do
    Emitter.emit("telemetry.event", %{size: 10}, %{key: :value})

    assert %{measurement: %{size: 1}, tags: %{}, unit: :unit} =
             CaptureReporter.recorded(pid, "telemetry.event")
  end

  test "can use measurement map in the event measurement calculation", %{capture: pid} do
    Emitter.emit("phoenix.endpoint.stop", %{duration: 100})

    assert %{measurement: %{duration: 100}, tags: %{}, unit: :unit} =
             CaptureReporter.recorded(pid, "phoenix.endpoint.stop")
  end

  test "emit/3 preserves the full metric name", %{capture: pid} do
    Emitter.emit("service.request", %{count: 3, duration: 5})

    assert %{measurement: %{count: 3}, tags: %{}} =
             CaptureReporter.recorded(pid, "service.request")

    assert %{measurement: %{duration: 5}, tags: %{}} =
             CaptureReporter.recorded(pid, "service.request")
  end

  test "prints tag values measurements", %{capture: pid} do
    Emitter.emit("http.request", %{response_time: 1000}, %{foo: :bar})

    assert %{measurement: %{response_time: 1000}, tags: %{bar: :baz}, unit: :unit} =
             CaptureReporter.recorded(pid, "http.request")
  end
end
