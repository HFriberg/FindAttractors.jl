using Test
using FindAttractors

const FA = FindAttractors

function oracle(next_value, max_input, n, ::Type{S}) where S
    value = S(n)
    seen = Set{S}()
    while true
        value > max_input(S) && return (:overflow, seen)
        push!(seen, value)
        value = next_value(value)
        value < n && return (:descent, seen)
        if value in seen
            cycle = Set{S}([value])
            v = next_value(value)
            while v != value
                push!(cycle, v)
                v = next_value(v)
            end
            return (:cycle, cycle)
        end
    end
end

function check_rule(next_value, max_input, starts, ::Type{S}) where S
    T = eltype(starts)
    cycle_from, cycle_to, overflow = T[], S[], T[]
    for n in starts
        empty!(cycle_from)
        empty!(cycle_to)
        empty!(overflow)
        FA.classify_orbit!(next_value, max_input, n, cycle_from, cycle_to, overflow)
        expected, cycle = oracle(next_value, max_input, n, S)
        actual = isempty(cycle_from) ? (isempty(overflow) ? :descent : :overflow) : :cycle
        @test actual == expected
        if actual == :cycle
            @test only(cycle_from) == n
            @test only(cycle_to) in cycle
        end
    end
end

classic(value) = ((v = 3 * value + 1); v >> trailing_zeros(v))
classic_max(::Type{T}) where T = T((typemax(T) - 1) ÷ 3)
alternate(value) = ((v = 5 * value + 3); v >> trailing_zeros(v))
alternate_max(::Type{T}) where T = T((typemax(T) - 3) ÷ 5)
full_max(::Type{T}) where T = typemax(T)

@testset "Orbit classification and promotion" begin
    check_rule(classic, classic_max, UInt8(1):UInt8(2):UInt8(255), UInt16)
    check_rule(alternate, alternate_max, UInt8(1):UInt8(2):UInt8(255), UInt16)
    check_rule(alternate, alternate_max, UInt8(1):UInt8(2):UInt8(255), UInt8)
    fail_parent(value) = error("stepped an unsafe input")
    low_max(::Type{T}) where T = T(10)
    cycle_from, cycle_to, overflow = UInt8[], UInt16[], UInt8[]
    FA.classify_orbit!(fail_parent, low_max, UInt8(11), cycle_from, cycle_to, overflow)
    @test overflow == [11]
    @test isempty(cycle_from)
    promote_parent(value) = (value <= classic_max(typeof(value)) || error("unsafe"); classic(value))
    check_rule(promote_parent, classic_max, UInt8(253):UInt8(2):UInt8(255), UInt16)
    max_then_zero(value) = value == typemax(typeof(value)) ? zero(value) : typemax(typeof(value))
    check_rule(max_then_zero, full_max, UInt8(1):UInt8(1):UInt8(255), UInt8)
    long_cycle(value) = value == typemax(typeof(value)) ? oftype(value, 2) : value + one(value)
    check_rule(long_cycle, full_max, UInt8(0):UInt8(1):UInt8(255), UInt8)
    for salt in (1, 7, 31)
        table = [UInt8(mod(17i*i + salt*i + 73, 256)) for i in 0:255]
        next_value = value -> table[Int(value) + 1]
        check_rule(next_value, full_max, UInt8(0):UInt8(1):UInt8(255), UInt8)
    end
end

@testset "Batches, callbacks and counts" begin
    pairs = Tuple{UInt64,UInt128}[]
    overflow = UInt64[]
    seen_starts = UInt64[]
    retained_buffers = Ref{Any}()
    function collect_batch(batch)
        append!(seen_starts, batch.starts)
        for thread_id in eachindex(batch.cycle_from)
            append!(pairs, zip(batch.cycle_from[thread_id], batch.cycle_to[thread_id]))
            append!(overflow, batch.overflow[thread_id])
        end
        retained_buffers[] = batch.cycle_from
    end
    starts = UInt64(1):UInt64(2):UInt64(10001)
    summary = find_attractors(classic, classic_max, starts;
                              extended_type=UInt128, log_iter_freq=1,
                              log_time_freq=0.0001, on_batch=collect_batch)
    @test seen_starts == collect(starts)
    @test pairs == [(UInt64(1), UInt128(1))]
    @test isempty(overflow)
    @test summary.processed == length(starts)
    @test summary.cycles == length(pairs)
    @test summary.overflow == length(overflow)
    @test all(isempty, retained_buffers[])
    @test summary.elapsed >= 0
    tail(value) = value == 1 ? oftype(value, 3) : value == 3 ? oftype(value, 5) : oftype(value, 3)
    batch_copy = Ref{Any}()
    summary = find_attractors(tail, full_max, UInt16(1):UInt16(1):UInt16(1);
        on_batch=b -> (batch_copy[] = deepcopy(b)))
    @test summary.cycles == 1
    @test only(vcat(batch_copy[].cycle_to...)) in (3, 5)
    io = IOBuffer()
    report_batch(batch_copy[]; io)
    @test occursin("1 -> ", String(take!(io)))
    summary = find_attractors(identity, full_max, UInt64(1):UInt64(1):UInt64(0);
                              on_batch=_ -> error("empty search called callback"))
    @test summary.processed == summary.cycles == summary.overflow == 0
    summary = find_attractors(alternate, alternate_max, UInt8(1):UInt8(2):UInt8(255);
                              on_batch=_ -> nothing)
    @test summary.overflow > 0
end

@testset "Contracts and inference" begin
    starts = UInt64(1):UInt64(2):UInt64(21)
    @test_throws ArgumentError find_attractors(classic, classic_max, starts; extended_type=UInt8)
    @test_throws ArgumentError find_attractors(classic, classic_max, starts; log_iter_freq=0)
    @test_throws ArgumentError find_attractors(classic, classic_max, starts; log_time_freq=0)
    @test_throws ArgumentError find_attractors(classic, classic_max, starts; log_time_freq=Inf)
    @test_throws ArgumentError find_attractors(identity, full_max, 2:-1:1)
    @test_throws ArgumentError find_attractors(identity, full_max, -1:1:1)
    @test_throws ArgumentError find_attractors(identity, full_max, Int8(1):Int8(1):Int8(5))
    @test_throws ArgumentError find_attractors(identity, full_max, big(1):big(1):big(5))
    @test_throws ArgumentError find_attractors(identity, _ -> 10, starts)
    @test (@inferred FA.trace_orbit(classic, classic_max, UInt64(27), UInt64(27))) isa Tuple{UInt64,UInt64}
    @test (@inferred FA.classify_orbit!(classic, classic_max, UInt64(27), UInt64[], UInt128[], UInt64[])) === nothing
    rule = let a=UInt64(3), b=UInt64(1)
        value -> ((v = a*value + b); v >> trailing_zeros(v))
    end
    @test find_attractors(rule, classic_max, starts; on_batch=_ -> nothing).cycles == 1
end

include(joinpath(@__DIR__, "..", "examples", "collatz_3n1.jl"))
include(joinpath(@__DIR__, "..", "examples", "collatz_5n3.jl"))

@testset "Examples" begin
    for (example, a, b) in ((Collatz3n1, 3, 1), (Collatz5n3, 5, 3))
        @test example.max_input(UInt64) == (typemax(UInt64) - b) ÷ a
        for n in UInt64(1):UInt64(2):UInt64(99)
            value = a * n + b
            @test example.next_value(n) == value >> trailing_zeros(value)
        end
    end
    @test Collatz3n1.main(["100"]).processed == 25
    @test Collatz5n3.main(["100"]).processed == 50
end

@testset "Range boundaries and loading side effects" begin
    summary = find_attractors(identity, full_max, UInt8(0):UInt8(1):UInt8(255);
                              on_batch=_ -> nothing)
    @test summary.processed == summary.cycles == 256
    summary = find_attractors(identity, full_max, Int16(0):Int16(1):Int16(255);
                              on_batch=_ -> nothing)
    @test summary.processed == summary.cycles == 256
    complete = UInt64(1):UInt64(2):typemax(UInt64)
    @test length(complete) == UInt64(1) << 63
    callback_seen = Ref(false)
    function stop_after_one(batch)
        @test eltype(batch.starts) == UInt64
        @test collect(batch.starts) == [UInt64(1)]
        callback_seen[] = true
        error("stop after first batch")
    end
    @test_throws ErrorException find_attractors(identity, full_max, complete;
        log_iter_freq=1, log_time_freq=eps(Float64), on_batch=stop_after_one)
    @test callback_seen[]
    @test which(show, (IO, UInt64)).module === Base
    copied = Ref{Any}()
    zero_max(::Type{T}) where T = zero(T)
    find_attractors(identity, zero_max, UInt8(1):UInt8(1):UInt8(1);
                   on_batch=b -> (copied[] = deepcopy(b)))
    io = IOBuffer()
    report_batch(copied[]; io, show_overflow=true)
    text = String(take!(io))
    @test occursin("1 -> overflow", text)
    @test !occursin("INF", text)
end

@testset "Reporting" begin
    batch = AttractorBatch(UInt64(3):UInt64(4):UInt64(11), [UInt64[]],
                           [UInt128[]], [UInt64[3]], 2.0, 2.0)
    io = IOBuffer()
    report_batch(batch; io)
    text = String(take!(io))
    @test occursin("speed=4.0e-6 [M/s], starts=1.5e-6 [M/s]", text)
    @test endswith(text, "1 overflow\n")
    report_batch(batch; io, show_overflow=true)
    @test endswith(String(take!(io)), "3 -> overflow\n")
end
